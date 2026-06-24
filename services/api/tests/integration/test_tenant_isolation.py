"""M0-7 acceptance proofs — tenant isolation enforced through real API endpoints.

Each test drives the live FastAPI app (real auth dependency, real asyncpg session,
real RLS) against a Postgres carrying migrations 0001-0016. Isolation here is proven
end-to-end, not mocked: the only thing distinguishing tenant A from tenant B is the
``company_id`` claim inside the bearer token.
"""

from __future__ import annotations

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

pytestmark = pytest.mark.integration

LEADS_URL = "/api/v1/leads"


async def _get_leads(client, token: str):
    return await client.get(LEADS_URL, headers={"Authorization": f"Bearer {token}"})


async def test_tenant_a_sees_only_its_own_leads(client, make_token, seed_two_tenants, tenant_ids):
    token = make_token(company_id=tenant_ids["A"], role="admin")
    r = await _get_leads(client, token)
    assert r.status_code == 200
    body = r.json()
    assert body["count"] == len(tenant_ids["A_leads"])
    assert {item["id"] for item in body["items"]} == set(tenant_ids["A_leads"])


async def test_tenant_a_cannot_access_tenant_b_data(
    client, make_token, seed_two_tenants, tenant_ids
):
    token = make_token(company_id=tenant_ids["A"], role="admin")
    r = await _get_leads(client, token)
    returned = {item["id"] for item in r.json()["items"]}
    assert returned.isdisjoint(set(tenant_ids["B_leads"]))


async def test_tenant_b_sees_only_its_own_leads(client, make_token, seed_two_tenants, tenant_ids):
    token = make_token(company_id=tenant_ids["B"], role="admin")
    r = await _get_leads(client, token)
    assert r.status_code == 200
    body = r.json()
    assert {item["id"] for item in body["items"]} == set(tenant_ids["B_leads"])


async def test_jwt_claim_injection_drives_isolation(
    client, make_token, seed_two_tenants, tenant_ids
):
    """Same endpoint + same code path, two tokens → two disjoint result sets.

    Since the SQL has no company filter, the only thing that can scope the rows is
    the injected ``company_id`` claim — so this proves claim injection works.
    """
    a = make_token(company_id=tenant_ids["A"], role="admin")
    b = make_token(company_id=tenant_ids["B"], role="manager")
    ids_a = {i["id"] for i in (await _get_leads(client, a)).json()["items"]}
    ids_b = {i["id"] for i in (await _get_leads(client, b)).json()["items"]}
    assert ids_a == set(tenant_ids["A_leads"])
    assert ids_b == set(tenant_ids["B_leads"])
    assert ids_a.isdisjoint(ids_b)


async def test_valid_token_for_empty_tenant_sees_nothing(
    client, make_token, seed_two_tenants, tenant_ids
):
    token = make_token(company_id=tenant_ids["empty"], role="admin")
    r = await _get_leads(client, token)
    assert r.status_code == 200
    assert r.json()["count"] == 0


async def test_missing_bearer_token_rejected(client, seed_two_tenants):
    r = await client.get(LEADS_URL)
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "missing_token"


async def test_token_without_tenant_claims_rejected(client, make_token, seed_two_tenants):
    token = make_token(include_app_metadata=False)
    r = await _get_leads(client, token)
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "missing_tenant_claims"


async def test_service_role_path_still_sees_all_tenants(settings, seed_two_tenants, tenant_ids):
    """The unscoped service path (BYPASSRLS) must keep working across tenants.

    Mirrors the backend-worker path that M0-4/M0-5 rely on: as ``service_role`` it
    sees both tenants' fixture rows, confirming the tenant dependency did not change
    service behaviour.
    """
    engine = create_async_engine(
        str(settings.database_url), connect_args={"statement_cache_size": 0}
    )
    try:
        async with engine.connect() as conn:
            await conn.execute(text("set role service_role"))
            total = await conn.execute(
                text("select count(*) from leads where company_id = any(:ids)"),
                {"ids": [tenant_ids["A"], tenant_ids["B"]]},
            )
            assert total.scalar_one() == len(tenant_ids["A_leads"]) + len(tenant_ids["B_leads"])
    finally:
        await engine.dispose()