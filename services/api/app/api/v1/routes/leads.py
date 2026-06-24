"""Leads — the M0-7 representative tenant-scoped endpoint.

``GET /leads`` lists leads for the authenticated caller's company. Note the SQL
has **no** ``where company_id = …`` clause: tenant isolation is enforced entirely
by Row-Level Security through the :func:`app.api.deps.get_tenant_db` session, which
injects the caller's verified ``company_id`` claim. This is intentional — it proves
the database boundary holds on its own. The full leads surface (filtering, writes)
lands with M1.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_tenant_db
from app.schemas.leads import LeadListResponse, LeadSummary

router = APIRouter(tags=["leads"])

_LIST_LEADS = text(
    """
    select id, name, phone, source::text as source,
           lead_status::text as lead_status, created_at
    from leads
    order by created_at desc, id
    limit :limit offset :offset
    """
)


@router.get("/leads", response_model=LeadListResponse, summary="List leads (tenant-scoped)")
async def list_leads(
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_tenant_db),
) -> LeadListResponse:
    result = await db.execute(_LIST_LEADS, {"limit": limit, "offset": offset})
    items = [LeadSummary(**row) for row in result.mappings().all()]
    return LeadListResponse(items=items, count=len(items))