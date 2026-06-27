"""DB-backed integration tests for M1.0 ``lead_events`` (migration 0018).

At M1.0 no HTTP endpoint reads or writes ``lead_events`` yet (the first writer is
the M1.3 ingestion orchestrator; the first tenant-facing reader is M1.9+). These
tests therefore prove the table's contract through the **real asyncpg/SQLAlchemy
driver** using the exact role + claim-injection plumbing the FastAPI DB-session
dependency uses in production:

    SET LOCAL ROLE <db_role>;
    select set_config('request.jwt.claims', '<app_metadata json>', true);

They assert the locked guarantees end-to-end through a live connection:
  * service_role (BYPASSRLS) is the write path; UPDATE/DELETE/TRUNCATE are denied
    by privilege (grant-based append-only — A1-2);
  * admin-only tenant read (A1-4): admin of A sees only A; non-admin sees nothing;
    cross-tenant reads are empty; anon is denied;
  * idempotency: ON CONFLICT DO NOTHING is a no-op; the same key under two
    companies both insert (tenant-scoped gate).

Skips cleanly when ``INTEGRATION_DATABASE_URL`` is unset, so ``make test`` stays
green offline. Fixture tenants use dedicated ``7d…`` / ``7e…`` UUIDs that cannot
collide with the dev seed (``1111…``) or the M0-6/M0-7 suites (``6…`` / ``7a…``/``7b…``).
"""

from __future__ import annotations

import json
import os

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

pytestmark = pytest.mark.asyncio

TENANT_A = "7d000000-0000-0000-0000-0000000000aa"
TENANT_B = "7e000000-0000-0000-0000-0000000000bb"
TENANT_EMPTY = "7f000000-0000-0000-0000-0000000000cc"  # valid tenant, no rows


def _async_url() -> str:
    url = os.getenv("INTEGRATION_DATABASE_URL")
    if not url:
        pytest.skip("INTEGRATION_DATABASE_URL not set; skipping DB-backed integration tests")
    if url.startswith("postgresql://"):
        url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
    elif url.startswith("postgres://"):
        url = url.replace("postgres://", "postgresql+asyncpg://", 1)
    return url


@pytest.fixture
async def engine():
    eng = create_async_engine(_async_url(), connect_args={"statement_cache_size": 0})
    try:
        yield eng
    finally:
        await eng.dispose()


async def _run(engine, db_role: str, company: str | None, role: str | None, sql: str,
               params: dict | None = None):
    """Execute ``sql`` inside one transaction as ``db_role`` under injected claims.

    Mirrors the production DB-session dependency. ``db_role`` is a fixed test
    constant (never user input), so interpolating it into SET LOCAL ROLE is safe.
    """
    async with engine.begin() as conn:
        if company is not None:
            claims = json.dumps({"app_metadata": {"company_id": company, "role": role}})
            await conn.execute(
                text("select set_config('request.jwt.claims', :c, true)"), {"c": claims}
            )
        await conn.execute(text(f"set local role {db_role}"))
        return await conn.execute(text(sql), params or {})


async def _count(engine, db_role, company, role) -> int:
    res = await _run(engine, db_role, company, role, "select count(*) from lead_events")
    return int(res.scalar_one())


@pytest.fixture
async def seed(engine):
    """Seed two tenants (A: 2 events, B: 1) via service_role; tear down as owner.

    Inserts run as ``service_role`` (the real worker write path). Teardown runs on
    the raw owner/superuser connection because append-only denies service_role the
    DELETE — confirming the grant boundary while keeping the suite self-cleaning.
    """
    # --- clean any prior fixture rows (owner connection) ---
    async with engine.begin() as conn:
        await conn.execute(
            text("delete from lead_events where company_id = any(:ids)"),
            {"ids": [TENANT_A, TENANT_B, TENANT_EMPTY]},
        )
        await conn.execute(
            text("delete from companies where id = any(:ids)"),
            {"ids": [TENANT_A, TENANT_B, TENANT_EMPTY]},
        )
    # --- insert via service_role ---
    async with engine.begin() as conn:
        await conn.execute(text("set local role service_role"))
        await conn.execute(
            text(
                "insert into companies(id, name, slug) values "
                "(:a,'IT M1 Tenant A','it-m1-a'),(:b,'IT M1 Tenant B','it-m1-b'),"
                "(:e,'IT M1 Tenant Empty','it-m1-empty')"
            ),
            {"a": TENANT_A, "b": TENANT_B, "e": TENANT_EMPTY},
        )
        await conn.execute(
            text(
                "insert into lead_events(company_id, source, external_lead_id, idempotency_key) values "
                "(:a,'meta','fb-1','meta:fb-1'),"
                "(:a,'google','g-1','google:g-1'),"
                "(:b,'meta','fb-1','meta:fb-1')"
            ),
            {"a": TENANT_A, "b": TENANT_B},
        )
    try:
        yield {"A": TENANT_A, "B": TENANT_B, "empty": TENANT_EMPTY}
    finally:
        async with engine.begin() as conn:
            await conn.execute(
                text("delete from lead_events where company_id = any(:ids)"),
                {"ids": [TENANT_A, TENANT_B, TENANT_EMPTY]},
            )
            await conn.execute(
                text("delete from companies where id = any(:ids)"),
                {"ids": [TENANT_A, TENANT_B, TENANT_EMPTY]},
            )


# ---------------------------------------------------------------------
# Write path (A1-1) + grant-based append-only (A1-2)
# ---------------------------------------------------------------------
async def test_service_role_can_insert(engine, seed):
    res = await _run(
        engine, "service_role", None, None,
        "insert into lead_events(company_id, source, idempotency_key) "
        "values (:a,'manual','svc-ins-1')",
        {"a": seed["A"]},
    )
    assert res.rowcount == 1


@pytest.mark.parametrize(
    "sql",
    [
        "update lead_events set payload = '{\"x\":1}' where true",
        "delete from lead_events where true",
        "truncate lead_events",
    ],
)
async def test_service_role_append_only(engine, seed, sql):
    with pytest.raises(Exception):  # insufficient_privilege
        await _run(engine, "service_role", None, None, sql)


# ---------------------------------------------------------------------
# Admin-only tenant isolation (A1-4)
# ---------------------------------------------------------------------
async def test_admin_sees_only_own_tenant(engine, seed):
    assert await _count(engine, "authenticated", seed["A"], "admin") == 2
    assert await _count(engine, "authenticated", seed["B"], "admin") == 1


async def test_empty_tenant_sees_nothing(engine, seed):
    assert await _count(engine, "authenticated", seed["empty"], "admin") == 0


async def test_non_admin_sees_nothing(engine, seed):
    assert await _count(engine, "authenticated", seed["A"], "agent") == 0
    assert await _count(engine, "authenticated", seed["A"], "manager") == 0


async def test_anon_denied(engine, seed):
    with pytest.raises(Exception):  # no grant, no policy
        await _run(engine, "anon", None, None, "select count(*) from lead_events")


# ---------------------------------------------------------------------
# Idempotency gate
# ---------------------------------------------------------------------
async def test_duplicate_key_conflict_is_noop(engine, seed):
    res = await _run(
        engine, "service_role", None, None,
        "insert into lead_events(company_id, source, idempotency_key) "
        "values (:a,'meta','meta:fb-1') on conflict (company_id, idempotency_key) do nothing",
        {"a": seed["A"]},
    )
    assert res.rowcount == 0
    # original row count for A is unchanged (still its 2 seeded events)
    assert await _count(engine, "authenticated", seed["A"], "admin") == 2


async def test_same_key_two_tenants_both_insert(engine, seed):
    res = await _run(
        engine, "service_role", None, None,
        "insert into lead_events(company_id, source, idempotency_key) values "
        "(:a,'api','cross:key'),(:b,'api','cross:key')",
        {"a": seed["A"], "b": seed["B"]},
    )
    assert res.rowcount == 2


async def test_duplicate_key_same_tenant_raises(engine, seed):
    with pytest.raises(Exception):  # unique_violation
        await _run(
            engine, "service_role", None, None,
            "insert into lead_events(company_id, source, idempotency_key) "
            "values (:a,'meta','meta:fb-1')",
            {"a": seed["A"]},
        )


# ---------------------------------------------------------------------
# FK ON DELETE RESTRICT protects the ledger (A1-3)
# ---------------------------------------------------------------------
async def test_company_delete_restricted_while_events_exist(engine, seed):
    with pytest.raises(Exception):  # foreign_key_violation
        await _run(
            engine, "service_role", None, None,
            "delete from companies where id = :a", {"a": seed["A"]},
        )
