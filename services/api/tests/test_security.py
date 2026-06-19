import uuid

import pytest
from fastapi import HTTPException

from app.api.deps import require_roles
from app.core.security import AuthError, authenticate
from app.schemas.auth import Principal, UserRole


def test_authenticate_happy_path(settings, make_token):
    company = str(uuid.uuid4())
    token = make_token(company_id=company, role="admin")
    principal = authenticate(token, settings)
    assert principal.role is UserRole.ADMIN
    assert str(principal.company_id) == company


def test_expired_token_rejected(settings, make_token):
    token = make_token(exp_delta=-3600)
    with pytest.raises(AuthError) as exc:
        authenticate(token, settings)
    assert exc.value.code == "invalid_token"


def test_bad_signature_rejected(settings, make_token):
    token = make_token(secret="a-completely-different-secret-0123456789xyz")
    with pytest.raises(AuthError) as exc:
        authenticate(token, settings)
    assert exc.value.code == "invalid_token"


def test_wrong_audience_rejected(settings, make_token):
    token = make_token(audience="anon")
    with pytest.raises(AuthError) as exc:
        authenticate(token, settings)
    assert exc.value.code == "invalid_token"


def test_missing_tenant_claims_rejected(settings, make_token):
    token = make_token(include_app_metadata=False)
    with pytest.raises(AuthError) as exc:
        authenticate(token, settings)
    assert exc.value.code == "missing_tenant_claims"


def test_unknown_role_rejected(settings, make_token):
    token = make_token(role="superuser")
    with pytest.raises(AuthError) as exc:
        authenticate(token, settings)
    assert exc.value.code == "invalid_role"


def test_malformed_uuid_rejected(settings, make_token):
    token = make_token(company_id="not-a-uuid")
    with pytest.raises(AuthError) as exc:
        authenticate(token, settings)
    assert exc.value.code == "invalid_claims"


@pytest.mark.asyncio
async def test_require_roles_allows_and_blocks():
    admin = Principal(user_id=uuid.uuid4(), company_id=uuid.uuid4(), role=UserRole.ADMIN)
    viewer = Principal(user_id=uuid.uuid4(), company_id=uuid.uuid4(), role=UserRole.VIEWER)
    guard = require_roles(UserRole.ADMIN, UserRole.MANAGER)

    assert await guard(admin) is admin

    with pytest.raises(HTTPException) as exc:
        await guard(viewer)
    assert exc.value.status_code == 403
    assert exc.value.detail["code"] == "insufficient_role"
