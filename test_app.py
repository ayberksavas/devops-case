import json
import logging

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


def test_metrics_endpoint_returns_prometheus_format(client):
    # Hit a real endpoint first so a series exists for the scrape to render.
    client.get("/ping")
    response = client.get("/metrics")
    assert response.status_code == 200
    assert response.content_type.startswith("text/plain")
    body = response.data.decode()
    assert "http_requests_total" in body
    assert "http_request_duration_seconds" in body


def test_request_id_is_generated_when_absent(client):
    response = client.get("/ping")
    rid = response.headers.get("X-Request-ID")
    assert rid is not None and len(rid) > 0


def test_request_id_is_echoed_when_provided(client):
    response = client.get("/ping", headers={"X-Request-ID": "deadbeef-1234"})
    assert response.headers.get("X-Request-ID") == "deadbeef-1234"


def test_json_formatter_emits_expected_fields():
    from app import JsonFormatter

    record = logging.LogRecord(
        name="app",
        level=logging.INFO,
        pathname=__file__,
        lineno=1,
        msg="request",
        args=(),
        exc_info=None,
    )
    record.request_id = "abc123"
    record.method = "GET"
    record.path = "/ping"
    record.status = 200
    record.duration_ms = 1.23
    line = JsonFormatter().format(record)
    payload = json.loads(line)
    assert payload["level"] == "INFO"
    assert payload["msg"] == "request"
    assert payload["request_id"] == "abc123"
    assert payload["method"] == "GET"
    assert payload["path"] == "/ping"
    assert payload["status"] == 200
    assert payload["duration_ms"] == 1.23
    assert payload["timestamp"].endswith("Z")
