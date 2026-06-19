"""Application configuration.

All runtime configuration is loaded from environment variables (or a local
``.env`` file in development) and validated once at import time via a cached
``Settings`` singleton. Nothing in this module performs I/O against external
services — it only declares and validates configuration.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field, PostgresDsn, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

Environment = Literal["local", "development", "staging", "production"]


class Settings(BaseSettings):
    """Strongly-typed application settings.

    Values are case-insensitive environment variables. In non-local
    environments the ``.env`` file is ignored and only the process
    environment is read.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ----- Application -------------------------------------------------- #
    app_name: str = Field(default="rytaine-leadai-api")
    app_env: Environment = Field(default="local")
    debug: bool = Field(default=False)
    api_v1_prefix: str = Field(default="/api/v1")
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = Field(
        default="INFO"
    )

    # ----- CORS --------------------------------------------------------- #
    # Comma-separated list of allowed origins for the dashboard, e.g.
    # "https://app.rytaine.ai,http://localhost:3000"
    cors_origins: list[str] = Field(default_factory=list)

    # ----- Database ----------------------------------------------------- #
    # Supabase Postgres connection string. Accepts a plain ``postgres://`` /
    # ``postgresql://`` URL and is normalised to the asyncpg driver.
    database_url: PostgresDsn = Field(
        default="postgresql+asyncpg://postgres:postgres@localhost:5432/rytaine"
    )
    db_pool_size: int = Field(default=5, ge=1, le=50)
    db_max_overflow: int = Field(default=10, ge=0, le=50)
    db_pool_timeout_seconds: int = Field(default=30, ge=1, le=120)
    db_echo: bool = Field(default=False)
    # Set 0 when connecting through a transaction-mode pgBouncer pooler
    # (Supabase port 6543), which does not support prepared statements.
    db_statement_cache_size: int = Field(default=100, ge=0)

    # ----- Auth (Supabase JWT) ----------------------------------------- #
    supabase_jwt_secret: str = Field(default="change-me-in-env")
    supabase_jwt_algorithm: str = Field(default="HS256")
    # Supabase signs end-user tokens with the "authenticated" audience.
    supabase_jwt_audience: str = Field(default="authenticated")
    supabase_jwt_leeway_seconds: int = Field(default=10, ge=0, le=300)

    @field_validator("database_url", mode="before")
    @classmethod
    def _coerce_async_driver(cls, value: object) -> object:
        """Normalise common Postgres URL prefixes to the asyncpg driver."""
        if isinstance(value, str):
            if value.startswith("postgresql+asyncpg://"):
                return value
            if value.startswith("postgresql://"):
                return "postgresql+asyncpg://" + value[len("postgresql://"):]
            if value.startswith("postgres://"):
                return "postgresql+asyncpg://" + value[len("postgres://"):]
        return value

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_csv_origins(cls, value: object) -> object:
        """Allow a comma-separated string for CORS origins."""
        if isinstance(value, str):
            if not value.strip():
                return []
            return [o.strip() for o in value.split(",") if o.strip()]
        return value


@lru_cache
def get_settings() -> Settings:
    """Return the process-wide cached settings singleton."""
    return Settings()
