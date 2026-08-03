"""
backend/tests/api/test_health.py
API tests for GET /health endpoint.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


class TestHealthEndpoint:
    def test_health_returns_200(self, client: TestClient):
        resp = client.get("/health")
        assert resp.status_code == 200

    def test_health_response_schema(self, client: TestClient):
        data = client.get("/health").json()
        assert "status" in data
        assert "version" in data
        assert "uptime_seconds" in data
        assert "api_status" in data

    def test_health_status_is_string(self, client: TestClient):
        data = client.get("/health").json()
        assert isinstance(data["status"], str)
        assert data["status"] in ("healthy", "degraded")

    def test_health_version_matches(self, client: TestClient):
        from app.core.config import get_settings
        data = client.get("/health").json()
        assert data["version"] == get_settings().VERSION

    def test_health_uptime_is_positive(self, client: TestClient):
        data = client.get("/health").json()
        assert data["uptime_seconds"] > 0

    def test_health_api_status_is_dict(self, client: TestClient):
        data = client.get("/health").json()
        assert isinstance(data["api_status"], dict)

    def test_health_has_gemini_status(self, client: TestClient):
        data = client.get("/health").json()
        assert "gemini" in data["api_status"]

    def test_health_has_whisper_status(self, client: TestClient):
        data = client.get("/health").json()
        assert "whisper" in data["api_status"]

    def test_health_has_easyocr_status(self, client: TestClient):
        data = client.get("/health").json()
        assert "easyocr" in data["api_status"]

    def test_root_returns_200(self, client: TestClient):
        resp = client.get("/")
        assert resp.status_code == 200

    def test_root_has_service_info(self, client: TestClient):
        data = client.get("/").json()
        assert "service" in data
        assert "version" in data
        assert "docs" in data
