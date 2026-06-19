"""Async database session factory.

A process-wide async engine + ``async_sessionmaker`` are created in the app
lifespan and disposed on shutdown. ``get_db`` yields a request-scoped session
and rolls back on error — endpoints own their commits. ``check_database`` is
the lightweight ``SELECT 1`` readiness probe.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import Settings

_engine: AsyncEngine | None = None
_sessionmaker: async_sessionmaker[AsyncSession] | None = None


def init_engine(settings: Settings) -> AsyncEngine:
    """Create the engine + sessionmaker once. Idempotent."""
    global _engine, _sessionmaker
    if _engine is None:
        _engine = create_async_engine(
            str(settings.database_url),
            echo=settings.db_echo,
            pool_pre_ping=True,
            pool_size=settings.db_pool_size,
            max_overflow=settings.db_max_overflow,
            pool_timeout=settings.db_pool_timeout_seconds,
            connect_args={"statement_cache_size": settings.db_statement_cache_size},
        )
        _sessionmaker = async_sessionmaker(
            _engine, expire_on_commit=False, class_=AsyncSession
        )
    return _engine


async def dispose_engine() -> None:
    """Dispose the engine on shutdown."""
    global _engine, _sessionmaker
    if _engine is not None:
        await _engine.dispose()
        _engine = None
        _sessionmaker = None


def get_sessionmaker() -> async_sessionmaker[AsyncSession]:
    if _sessionmaker is None:
        raise RuntimeError(
            "Database engine is not initialised; call init_engine() in lifespan."
        )
    return _sessionmaker


async def get_db() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency: a request-scoped session, rolled back on error."""
    sessionmaker = get_sessionmaker()
    async with sessionmaker() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise


async def check_database() -> bool:
    """Readiness probe. Returns True if the database answers ``SELECT 1``."""
    try:
        sessionmaker = get_sessionmaker()
    except RuntimeError:
        return False
    try:
        async with sessionmaker() as session:
            await session.execute(text("SELECT 1"))
        return True
    except Exception:
        return False
