"""Shared response models: the error envelope and health payloads."""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel


class ErrorDetail(BaseModel):
    code: str
    message: str
    details: Any | None = None


class ErrorResponse(BaseModel):
    """The approved error envelope: ``{"error": {"code", "message", "details?"}}``."""

    error: ErrorDetail


class HealthResponse(BaseModel):
    status: str
    service: str
    version: str


class ReadinessResponse(BaseModel):
    status: str  # "ok" | "degraded"
    database: str  # "up" | "down"
