"""Authentication value objects.

Framework-agnostic: no FastAPI imports here so these can be reused by workers
and the voice service in later milestones.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from uuid import UUID


class UserRole(str, Enum):
    """Application roles. Mirrors the ``user_role`` enum in the database."""

    ADMIN = "admin"
    MANAGER = "manager"
    AGENT = "agent"
    VIEWER = "viewer"


@dataclass(frozen=True)
class Principal:
    """The authenticated caller, derived from a verified Supabase JWT."""

    user_id: UUID
    company_id: UUID
    role: UserRole
    email: str | None = None
