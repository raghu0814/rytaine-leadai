"""FastAPI auth dependencies.

``get_current_principal`` resolves the bearer token to a :class:`Principal`;
``require_roles`` is the authorization guard used by protected routes in later
milestones. M0-1 ships no protected routes — these are wired and tested only.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from fastapi import Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import Settings, get_settings
from app.core.security import AuthError, authenticate
from app.db.session import get_sessionmaker
from app.db.tenant import set_tenant_context
from app.schemas.auth import Principal, UserRole

_bearer = HTTPBearer(auto_error=False)


def _settings_dep(request: Request) -> Settings:
    return getattr(request.app.state, "settings", None) or get_settings()

async def get_current_principal(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    settings: Settings = Depends(_settings_dep),
) -> Principal:
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status_code=401,
            detail={"code": "missing_token", "message": "Authorization bearer token required"},
        )
    try:
        return authenticate(credentials.credentials, settings)
    except AuthError as exc:
        raise HTTPException(
            status_code=401, detail={"code": exc.code, "message": exc.message}
        ) from exc


def require_roles(*roles: UserRole):
    """Return a dependency that allows only the given roles (else HTTP 403)."""
    allowed = set(roles)

    async def _guard(principal: Principal = Depends(get_current_principal)) -> Principal:
        if principal.role not in allowed:
            raise HTTPException(
                status_code=403,
                detail={
                    "code": "insufficient_role",
                    "message": "You do not have permission to perform this action",
                },
            )
        return principal

    return _guard

async def get_tenant_db(
    principal: Principal = Depends(get_current_principal),
) -> AsyncIterator[AsyncSession]:
    sessionmaker = get_sessionmaker()

    async with sessionmaker() as session:
        try:
            await set_tenant_context(session, principal)
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
