import pytest

from app import app


@pytest.fixture
def client():
    app.testing = True
    with app.test_client() as test_client:
        yield test_client


def test_ping_returns_pong(client):
    response = client.get("/ping")
    assert response.status_code == 200
    assert response.data.decode().strip() == "pong"
    assert response.content_type.startswith("text/plain")


def test_healthz_returns_ok(client):
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json == {"status": "ok"}


def test_version_returns_build_sha(client, monkeypatch):
    monkeypatch.setattr("app.BUILD_SHA", "test-sha-abc123")
    response = client.get("/version")
    assert response.status_code == 200
    assert response.json == {"sha": "test-sha-abc123"}
