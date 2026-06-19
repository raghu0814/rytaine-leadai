"""Test fixtures: settings, a Supabase-style JWT factory, and an ASGI client.

The suite is fully offline — no database is required; the readiness probe is
patched per-test where needed.
"""

from __future__ import annotations

import time
import uuid

import jwt
import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings
from app.main import create_app

TEST_SECRET = "test-jwt-secret-please-change-0123456789abcd"


@pytest.fixture
def settings() -> Settings:
    return Settings(
        supabase_jwt_secret=TEST_SECRET,
        app_env="local",
        cors_origins=[],
    )


@pytest.fixture
def make_token(settings: Settings):
    """Factory producing signed Supabase-style JWTs for tests."""

    def _make(
        *,
        sub: str | None = None,
        company_id: str | None = None,
        role: str = "admin",
        exp_delta: int = 3600,
        secret: str | None = None,
        audience: str = "authenticated",
        include_app_metadata: bool = True,
    ) -> str:
        now = int(time.time())
        payload: dict = {
            "sub": sub or str(uuid.uuid4()),
            "aud": audience,
            "iat": now,
            "exp": now + exp_delta,
        }
        if include_app_metadata:
            payload["app_metadata"] = {
                "company_id": company_id or str(uuid.uuid4()),
                "role": role,
            }
        return jwt.encode(payload, secret or settings.supabase_jwt_secret, algorithm="HS256")

    return _make


@pytest.fixture
async def client(settings: Settings):
    app = create_app(settings)
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
