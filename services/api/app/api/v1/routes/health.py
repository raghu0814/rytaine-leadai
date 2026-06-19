"""Health probes.

``/health``        — liveness: process is up, no external dependencies touched.
``/health/ready``  — readiness: probes the database; reports ``degraded`` at
                     HTTP 200 (not 5xx) if the pool is unavailable, so the
                     orchestrator can distinguish "alive" from "ready".
"""

from __future__ import annotations

from fastapi import APIRouter, Request

from app import __version__
from app.db import session as db_session
from app.schemas.common import HealthResponse, ReadinessResponse

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse, summary="Liveness probe")
async def health(request: Request) -> HealthResponse:
    settings = request.app.state.settings
    return HealthResponse(status="ok", service=settings.app_name, version=__version__)


@router.get("/health/ready", response_model=ReadinessResponse, summary="Readiness probe")
async def readiness() -> ReadinessResponse:
    ok = await db_session.check_database()
    return ReadinessResponse(
        status="ok" if ok else "degraded",
        database="up" if ok else "down",
    )
