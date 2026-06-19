import app.db.session as db_session


async def test_liveness_ok(client):
    r = await client.get("/api/v1/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["service"] == "rytaine-leadai-api"
    assert "version" in body


async def test_liveness_sets_request_id_header(client):
    r = await client.get("/api/v1/health")
    assert r.headers.get("X-Request-ID")


async def test_readiness_ok_when_db_up(client, monkeypatch):
    async def _ok() -> bool:
        return True

    monkeypatch.setattr(db_session, "check_database", _ok)
    r = await client.get("/api/v1/health/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
    assert r.json()["database"] == "up"


async def test_readiness_degraded_when_db_down(client, monkeypatch):
    async def _down() -> bool:
        return False

    monkeypatch.setattr(db_session, "check_database", _down)
    r = await client.get("/api/v1/health/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "degraded"
    assert r.json()["database"] == "down"


async def test_error_envelope_on_404(client):
    r = await client.get("/api/v1/does-not-exist")
    assert r.status_code == 404
    body = r.json()
    assert "error" in body
    assert "code" in body["error"]
    assert "message" in body["error"]
