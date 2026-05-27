from __future__ import annotations

import re

from fastapi.testclient import TestClient

from bilin_api.main import app, cors_allowed_origins, cors_origin_regex


def test_cors_origin_regex_defaults_to_loopback_only(monkeypatch) -> None:
    monkeypatch.delenv("BILIN_ALLOW_LAN_ORIGINS", raising=False)

    pattern = cors_origin_regex()

    assert re.match(pattern, "http://127.0.0.1:5173")
    assert re.match(pattern, "http://localhost:5173")
    assert not re.match(pattern, "http://192.168.124.4:5173")
    assert not re.match(pattern, "http://8.8.8.8:5173")


def test_cors_allowed_origins_accepts_exact_lan_origin(monkeypatch) -> None:
    monkeypatch.setenv(
        "BILIN_ALLOWED_ORIGINS",
        "http://192.168.124.4:5173,http://127.0.0.1:5173",
    )

    origins = cors_allowed_origins()

    assert "http://192.168.124.4:5173" in origins
    assert "http://10.0.0.2:5173" not in origins


def test_api_token_blocks_non_health_requests(monkeypatch) -> None:
    monkeypatch.setenv("BILIN_API_TOKEN", "test-token")

    with TestClient(app) as client:
        health = client.get("/health")
        blocked = client.get("/libraries")
        allowed = client.get("/libraries", headers={"Authorization": "Bearer test-token"})

    assert health.status_code == 200
    assert blocked.status_code == 401
    assert allowed.status_code == 200
