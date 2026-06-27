"""DB-backed integration tests for the 0019 full-schema privilege floor.

These prove — through the **real asyncpg/SQLAlchemy driver**, using the same
``SET LOCAL ROLE`` plumbing the FastAPI DB-session dependency uses in production —
that after migration 0019 the Supabase platform default-privilege over-grant is
gone and no role can exceed its intended surface:

  * TRUNCATE is denied for anon, authenticated, AND service_role on every
    application table (TRUNCATE is not subject to RLS, so the privilege is the
    only guard);
  * service_role (BYPASSRLS) is denied UPDATE/DELETE on the append-only tables
    (usage_logs, audit_logs) — append-only holds at the grant layer;
  * anon holds no table privilege at all.

Skips cleanly when ``INTEGRATION_DATABASE_URL`` is unset, so ``make test`` stays
green offline. Read-only/destructive attempts run inside transactions that are
always rolled back, so the suite never mutates data.
"""

from __future__ import annotations

import os

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

pytestmark = pytest.mark.asyncio

# Representative coverage: two append-only tables + two operational tables.
IMMUTABLE_TABLES = ["usage_logs", "audit_logs"]
OPERATIONAL_TABLES = ["leads", "companies"]
ALL_SAMPLE_TABLES = IMMUTABLE_TABLES + OPERATIONAL_TABLES
ALL_ROLES = ["anon", "authenticated", "service_role"]


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


async def _attempt(engine, db_role: str, sql: str):
    """Run ``sql`` as ``db_role`` in a transaction that is always rolled back.

    ``db_role`` is a fixed test constant (never user input), so interpolating it
    into SET LOCAL ROLE is safe.
    """
    async with engine.connect() as conn:
        trans = await conn.begin()
        try:
            await conn.execute(text(f"set local role {db_role}"))
            await conn.execute(text(sql))
        finally:
            await trans.rollback()


@pytest.mark.parametrize("db_role", ALL_ROLES)
@pytest.mark.parametrize("table", ALL_SAMPLE_TABLES)
async def test_truncate_denied_for_every_role(engine, db_role, table):
    """No role may TRUNCATE any application table (RLS-immune; privilege is the guard)."""
    with pytest.raises(Exception):
        await _attempt(engine, db_role, f"truncate table public.{table}")


@pytest.mark.parametrize("op", ["update public.{t} set created_at = created_at where false",
                                "delete from public.{t} where false"])
@pytest.mark.parametrize("table", IMMUTABLE_TABLES)
async def test_service_role_cannot_mutate_append_only(engine, op, table):
    """service_role (BYPASSRLS) holds SELECT+INSERT only on usage_logs/audit_logs."""
    with pytest.raises(Exception):
        await _attempt(engine, "service_role", op.format(t=table))


@pytest.mark.parametrize("table", ALL_SAMPLE_TABLES)
async def test_anon_has_no_table_access(engine, table):
    """anon holds no grant on any application table; even SELECT is denied by privilege."""
    with pytest.raises(Exception):
        await _attempt(engine, "anon", f"select 1 from public.{table} limit 1")
