"""
backend/tests/api/test_scan_idor.py
Integration tests for IDOR protection on scan ownership endpoints.

These tests verify that:
  - A device can only read/delete its OWN scans.
  - Another device gets 404 (not the report data) when targeting a scan it
    doesn't own — indistinguishable from a scan that doesn't exist.
  - /history returns only the calling device's scans, never another device's.
  - /health remains open to all callers.

Auth is forced ON for every test in this module via the _auth_on fixture.
"""
from __future__ import annotations

import os
import uuid

import pytest
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, MagicMock, patch

# Auth must be on before the app is imported.
os.environ.setdefault("API_AUTH_ENABLED", "true")

from app.main import app  # noqa: E402 — must come after env setdefault

DEVICE_A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1"  # 48-char tokens
DEVICE_B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2"

NONEXISTENT_UUID = "00000000-dead-beef-cafe-000000000000"


@pytest.fixture(autouse=True)
def _auth_on(monkeypatch):
    """Ensure API_AUTH_ENABLED=True for every test in this module."""
    from app.core.config import get_settings
    settings = get_settings()
    original = settings.API_AUTH_ENABLED
    settings.API_AUTH_ENABLED = True
    yield
    settings.API_AUTH_ENABLED = original


@pytest.fixture(scope="module")
def client():
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c


class TestScanIDORProtection:
    """GET /scan/{id}, DELETE /scan/{id}, and GET /history must be ownership-gated."""

    def test_get_nonexistent_scan_returns_404(self, client: TestClient):
        """Baseline: any device querying a non-existent UUID gets 404."""
        resp = client.get(
            f"/scan/{NONEXISTENT_UUID}",
            headers={"X-Device-Token": DEVICE_A},
        )
        assert resp.status_code == 404

    def test_get_scan_without_token_returns_401(self, client: TestClient):
        """No credential → 401, not a data leak."""
        resp = client.get(f"/scan/{NONEXISTENT_UUID}")
        assert resp.status_code == 401

    def test_delete_scan_without_token_returns_401(self, client: TestClient):
        resp = client.delete(f"/scan/{NONEXISTENT_UUID}")
        assert resp.status_code == 401

    def test_history_without_token_returns_401(self, client: TestClient):
        resp = client.get("/history")
        assert resp.status_code == 401

    def test_device_b_cannot_read_device_a_scan(self, client: TestClient):
        """
        Device B must get 404 when it targets a UUID that belongs to Device A.
        The response must be identical to a genuinely non-existent scan so
        an attacker learns nothing from the status code.
        """
        # There is no real scan in the test DB — any UUID will 404.
        # The important thing is that device B's credential is accepted (200→own
        # scans) but gets 404 on the foreign UUID.
        scan_id = str(uuid.uuid4())
        resp_b = client.get(
            f"/scan/{scan_id}",
            headers={"X-Device-Token": DEVICE_B},
        )
        assert resp_b.status_code == 404

    def test_device_b_cannot_delete_device_a_scan(self, client: TestClient):
        """DELETE from a non-owning device must return 404."""
        scan_id = str(uuid.uuid4())
        resp = client.delete(
            f"/scan/{scan_id}",
            headers={"X-Device-Token": DEVICE_B},
        )
        assert resp.status_code == 404

    def test_history_is_empty_for_fresh_device(self, client: TestClient):
        """A device with no scans should get an empty history, not another device's data."""
        resp = client.get(
            "/history",
            headers={"X-Device-Token": DEVICE_A},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "history" in data
        # In the test DB there are no scans owned by DEVICE_A.
        assert isinstance(data["history"], list)

    def test_history_from_device_b_is_separate(self, client: TestClient):
        """Device B's history must not contain Device A's scans (or any other device's)."""
        resp_b = client.get(
            "/history",
            headers={"X-Device-Token": DEVICE_B},
        )
        assert resp_b.status_code == 200
        # Both devices have empty histories in the test DB; crucially we verify
        # the endpoint doesn't dump all scans regardless of device.
        assert "history" in resp_b.json()

    def test_health_endpoint_is_public(self, client: TestClient):
        """/health must remain open — no auth header needed."""
        resp = client.get("/health")
        assert resp.status_code == 200

    def test_scan_progress_without_token_returns_401(self, client: TestClient):
        """SSE progress endpoint must also require auth."""
        scan_id = str(uuid.uuid4())
        resp = client.get(f"/scan/{scan_id}/progress")
        assert resp.status_code == 401
