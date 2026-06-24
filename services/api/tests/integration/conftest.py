"""Fixtures for the DB-backed M0-7 integration tests.

Overrides the offline ``settings``/``client`` fixtures (subpackage conftest takes
precedence) to point the app at a real Postgres given by ``INTEGRATION_DATABASE_URL``
and to initialise the engine the app's session dependency reads. All DB-backed
fixtures ``pytest.skip`` cleanly when the URL is absent, so ``make test`` stays
green without a database.

Tenant fixtures use dedicated ``7a…`` / ``7b…`` UUIDs that cannot collide with the
dev seed (``1111…``) or the M0-6 suite (``6a…`` / ``6b…``); every assertion is scoped
to this fixture set, so the tests are seed-independent. Fixture rows are inserted
and torn down via a separate ``service_role`` (BYPASSRLS) connection — the same
class of path the backend workers use — exercising requirement 5's service path.
"""

from __future__ import annotations

import os

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

import app.db.session as db_session
from app.core.config import Settings
from app.main import create_app

# Must match the secret the offline `make_token` factory signs with (tests/conftest.py),
# since that fixture is reused here to mint tenant tokens.
TEST_SECRET = "test-jwt-secret-please-change-0123456789abcd"

# Dedicated, seed- and M0-6-independent fixture identifiers.
TENANT_A = "7a000000-0000-0000-0000-0000000000aa"
TENANT_B = "7b000000-0000-0000-0000-0000000000bb"
A_LEADS = [
    "7a000000-0000-0000-0000-00000000a001",
    "7a000000-0000-0000-0000-00000000a002",
]
B_LEADS = [
    "7b000000-0000-0000-0000-00000000b001",
    "7b000000-0000-0000-0000-00000000b002",
]
# A valid tenant with no rows — proves visibility is RLS-driven, not app-side.
TENANT_EMPTY = "7c000000-0000-0000-0000-0000000000cc"


@pytest.fixture(scope="session")
def integration_db_url() -> str:
    url = os.getenv("INTEGRATION_DATABASE_URL")
    if not url:
        pytest.skip("INTEGRATION_DATABASE_URL not set; skipping DB-backed integration tests")
    return url


@pytest.fixture
def settings(integration_db_url: str) -> Settings:
    """Override the offline settings: real DB + matching JWT secret."""
    return Settings(
        database_url=integration_db_url,
        supabase_jwt_secret=TEST_SECRET,
        app_env="local",
        # 0 is required on the transaction pooler and harmless on a direct connection.
        db_statement_cache_size=0,
        cors_origins=[],
    )


@pytest.fixture
def tenant_ids() -> dict:
    return {
        "A": TENANT_A,
        "B": TENANT_B,
        "A_leads": A_LEADS,
        "B_leads": B_LEADS,
        "empty": TENANT_EMPTY,
    }


async def _delete_fixtures(conn) -> None:
    await conn.execute(
        text("delete from leads where company_id = any(:ids)"),
        {"ids": [TENANT_A, TENANT_B]},
    )
    await conn.execute(
        text("delete from companies where id = any(:ids)"),
        {"ids": [TENANT_A, TENANT_B]},
    )


@pytest.fixture
async def seed_two_tenants(settings: Settings):
    """Insert two companies + two leads each via a service_role (BYPASSRLS) connection.

    Idempotent: clears the fixture set first. Tears the rows down afterwards.
    """
    engine = create_async_engine(
        str(settings.database_url), connect_args={"statement_cache_size": 0}
    )
    try:
        async with engine.begin() as conn:
            await conn.execute(text("set role service_role"))
            await _delete_fixtures(conn)
            await conn.execute(
                text(
                    "insert into companies(id, name, slug) values "
                    "(:a, 'IT Tenant A', 'it-tenant-a'), (:b, 'IT Tenant B', 'it-tenant-b')"
                ),
                {"a": TENANT_A, "b": TENANT_B},
            )
            for company, leads in ((TENANT_A, A_LEADS), (TENANT_B, B_LEADS)):
                for lead_id in leads:
                    await conn.execute(
                        text(
                            "insert into leads(id, company_id, phone, source) "
                            "values (:id, :company, :phone, 'manual')"
                        ),
                        {"id": lead_id, "company": company, "phone": "+9190000" + lead_id[-4:]},
                    )
        yield {"A": TENANT_A, "B": TENANT_B, "A_leads": A_LEADS, "B_leads": B_LEADS}
        async with engine.begin() as conn:
            await conn.execute(text("set role service_role"))
            await _delete_fixtures(conn)
    finally:
        await engine.dispose()


@pytest.fixture
async def client(settings: Settings):
    """ASGI client with the app's engine initialised against the real DB."""
    db_session.init_engine(settings)
    app = create_app(settings)
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as c:
            yield c
    finally:
        await db_session.dispose_engine()