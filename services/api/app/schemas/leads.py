"""Response models for the leads endpoint (M0-7 representative tenant route).

Read-only projection — a small, safe subset of ``public.leads`` columns. The full
lead model and write paths arrive with M1 (Lead Ingestion).
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class LeadSummary(BaseModel):
    """A tenant-visible lead row, as returned by ``GET /leads``."""

    id: UUID
    name: str | None = None
    phone: str
    source: str
    lead_status: str
    created_at: datetime


class LeadListResponse(BaseModel):
    """Envelope for a page of leads."""

    items: list[LeadSummary]
    count: int