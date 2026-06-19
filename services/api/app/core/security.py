"""JWT verification — framework-agnostic.

Verifies a Supabase-issued HS256 token and derives a :class:`Principal`.
Identity claims (``company_id``, ``role``) are read **only** from
``app_metadata`` (server-managed) per the locked auth model — never from
``user_metadata`` or the request body.
"""

from __future__ import annotations

from uuid import UUID

import jwt
from jwt import InvalidTokenError

from app.core.config import Settings
from app.schemas.auth import Principal, UserRole


class AuthError(Exception):
    """Raised on any authentication/authorization failure."""

    def __init__(self, code: str, message: str) -> None:
        self.code = code
        self.message = message
        super().__init__(message)


def decode_token(token: str, settings: Settings) -> dict:
    """Verify a JWT's signature and standard claims, returning the payload.

    Raises :class:`AuthError` on any verification failure.
    """
    try:
        return jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=[settings.supabase_jwt_algorithm],
            audience=settings.supabase_jwt_audience,
            leeway=settings.supabase_jwt_leeway_seconds,
            options={"require": ["exp", "sub"]},
        )
    except InvalidTokenError as exc:
        raise AuthError("invalid_token", "Token verification failed") from exc


def principal_from_payload(payload: dict) -> Principal:
    """Build a :class:`Principal` from a verified JWT payload.

    ``company_id`` and ``role`` are read from ``app_metadata`` (server-managed)
    and must both be present. Anything else is treated as an unauthorised token.
    """
    sub = payload.get("sub")
    app_metadata = payload.get("app_metadata") or {}
    company_id = app_metadata.get("company_id")
    raw_role = app_metadata.get("role")

    if not sub or not company_id or not raw_role:
        raise AuthError(
            "missing_tenant_claims",
            "Token is missing required company_id/role claims",
        )

    try:
        user_id = UUID(str(sub))
        tenant_id = UUID(str(company_id))
    except (ValueError, TypeError) as exc:
        raise AuthError("invalid_claims", "Token contains malformed identifiers") from exc

    try:
        role = UserRole(str(raw_role))
    except ValueError as exc:
        raise AuthError("invalid_role", f"Unknown role '{raw_role}'") from exc

    return Principal(
        user_id=user_id,
        company_id=tenant_id,
        role=role,
        email=payload.get("email"),
    )


def authenticate(token: str, settings: Settings) -> Principal:
    """Verify ``token`` and return the resolved :class:`Principal`."""
    payload = decode_token(token, settings)
    return principal_from_payload(payload)
