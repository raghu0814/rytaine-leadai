"""Declarative base.

ORM models land here in later milestones (M1+). For M0-1 this only provides
the shared ``Base`` so the metadata and session machinery are wired and ready.
The canonical schema continues to live in ``supabase/migrations`` — these
models will mirror it, not own it.
"""

from __future__ import annotations

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """Base class for all ORM models."""
