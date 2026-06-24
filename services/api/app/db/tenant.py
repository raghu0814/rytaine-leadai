"""Tenant context injection for the request-scoped DB session.

This is the database half of the M0-4 enforcement contract. Given a verified
:class:`Principal`, :func:`set_tenant_context` injects the caller's identity into
the **current transaction** so that the frozen RLS helpers
``current_company_id()`` / ``current_user_role()`` (migration ``0014``) resolve and
the RLS policies (``0015``/``0016``) engage:

* ``set_config('request.jwt.claims', <json>, is_local := true)`` — the JWT payload
  shaped exactly as the helpers read it (``app_metadata.company_id`` / ``role``).
  Bind-parameterised; ``is_local=true`` scopes it to the transaction (the
  injection-safe equivalent of ``SET LOCAL request.jwt.claims = '…'``, which cannot
  take a bind parameter).
* ``SET LOCAL ROLE authenticated`` — drops from the (BYPASSRLS) connection role to a
  non-privileged role so RLS is actually evaluated. ``SET LOCAL`` is reset at
  transaction end, so nothing leaks across pooled connections — this is what makes
  the approach correct on the Supavisor transaction pooler.

The statement order (claims first, then role) mirrors the validated M0-6 harness.
This module is intentionally free of any FastAPI / web-layer imports so it can be
reused by background workers and the voice service in later milestones.
"""

from __future__ import annotations

import json

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.schemas.auth import Principal

# Fixed, non-BYPASSRLS role the app assumes for tenant traffic. A literal (role
# names cannot be bound), kept here so there is a single source of truth.
AUTHENTICATED_ROLE = "authenticated"

_SET_CLAIMS = text("select set_config('request.jwt.claims', :claims, true)")
# Role name is a trusted module constant, never user input — safe to inline.
_SET_ROLE = text(f"set local role {AUTHENTICATED_ROLE}")


def build_claims(principal: Principal) -> str:
    """Serialise a principal into the exact JWT-claims JSON the RLS helpers read.

    Shape: ``{"app_metadata": {"company_id": "<uuid>", "role": "<role>"}}``.
    """
    return json.dumps(
        {
            "app_metadata": {
                "company_id": str(principal.company_id),
                "role": principal.role.value,
            }
        }
    )


async def set_tenant_context(session: AsyncSession, principal: Principal) -> None:
    """Inject ``principal``'s claims + drop to ``authenticated`` on ``session``.

    Must run inside the same transaction as the subsequent tenant queries; the
    settings are transaction-local and are discarded on commit/rollback. The first
    ``execute`` autobegins the transaction on a fresh ``AsyncSession``.

    The claims GUC is never set to an empty string (only a valid JSON object),
    because the ``0014`` helpers raise on an empty ``request.jwt.claims`` value.
    """
    await session.execute(_SET_CLAIMS, {"claims": build_claims(principal)})
    await session.execute(_SET_ROLE)