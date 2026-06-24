"""v1 API aggregator. Routers are mounted here under the configured prefix."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1.routes import health as health_routes
from app.api.v1.routes import leads as leads_routes

api_router = APIRouter()
api_router.include_router(health_routes.router)
api_router.include_router(leads_routes.router)