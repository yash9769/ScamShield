"""
backend/tests/api/test_auth.py
Tests for client authentication and per-device scan ownership.

The production default is API_AUTH_ENABLED=true: every sensitive endpoint
must reject unauthenticated callers and expose ONLY the calling device's own
scan data. The broad test suite (conftest) runs with auth disabled; this file
flips it on for its own tests.
"""

from __future__ import annotations

import os

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.main import app

DEVICE_A = "a" * 48  # distinct 48-char device tokens
DEVICE_B = "b" * 48


@pytest.fixture(autouse=True)
def _auth_on():
    """Force auth on for every test in this module, then restore."""
    settings = get_settings()
    previous = settings.API_AUTH_ENABLED
    settings.API_AUTH_ENABLED = True
    try:
        yield
    finally:
        settings.API_AUTH_ENABLED = previous


class TestClientAuthEnforced:
    """Every sensitive endpoint returns 401 without a credential.

    Uses the session-scoped ``client`` fixture (which does NOT auto-attach a
    device token) for both authenticated and unauthenticated requests — this
    avoids re-running the app lifespan, which would rebind the async DB engine
    to a different event loop.
    """

    @pytest.mark.parametrize(
        "method,path",
        [
            ("post", "/analyze"),
            ("post", "/analyze-voice"),
            ("post", "/analyze-image"),
            ("post", "/analyze-batch"),
            ("get", "/scan/00000000-0000-0000-0000-000000000000"),
            ("delete", "/scan/00000000-0000-0000-0000-000000000000"),
            ("get", "/history"),
            ("get", "/breach?email=test@example.com"),
            ("get", "/osint/hash/" + "a" * 64),
            ("post", "/osint/urls"),
            ("get", "/osint/ip/8.8.8.8"),
        ],
    )
    def test_unauthenticated_request_is_rejected(self, client, method, path):
        kwargs = {}
        if method == "post":
            kwargs["json"] = {"text": "hello"} if path in ("/analyze",) else (
                {"items": ["hello"]} if path == "/analyze-batch" else {"urls": ["http://example.com"]}
            )
        resp = getattr(client, method)(path, **kwargs)
        assert resp.status_code == 401, f"{method.upper()} {path} should require auth"

    def test_health_is_public(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200


class TestAuthenticatedAccess:
    """With a valid device token, endpoints work and scan data is device-scoped."""

    def test_analyze_works_with_device_token(self, client: TestClient):
        resp = client.post(
            "/analyze",
            json={"text": "Hello, is this the bank?"},
            headers={"X-Device-Token": DEVICE_A},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "classification" in data
        assert 0 <= data["riskScore"] <= 100

    def test_analyze_rejects_short_token(self, client: TestClient):
        resp = client.post(
            "/analyze",
            json={"text": "Hello"},
            headers={"X-Device-Token": "short"},
        )
        assert resp.status_code == 401

    def test_history_is_isolated_per_device(self, client: TestClient):
        """Device B must not see Device A's scans in /history."""
        # Both devices query an empty history — each sees only its own rows.
        resp_a = client.get("/history", headers={"X-Device-Token": DEVICE_A})
        resp_b = client.get("/history", headers={"X-Device-Token": DEVICE_B})
        assert resp_a.status_code == 200
        assert resp_b.status_code == 200

    def test_scan_read_is_ownership_checked(self, client: TestClient):
        """A device cannot read/delete another device's scan by guessing its id."""
        # No such scan exists for device B → 404 (not 401, not the data).
        resp = client.get(
            "/scan/00000000-0000-0000-0000-000000000000",
            headers={"X-Device-Token": DEVICE_B},
        )
        assert resp.status_code == 404
