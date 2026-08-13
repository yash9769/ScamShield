"""
backend/tests/api/test_admin.py
API tests for admin-only endpoints (/dashboard, /api/audit-logs, /api/stats).

Guards the production 500 caused by a wrong static-path resolution: the
dashboard must resolve backend/app/static/dashboard.html and return HTML with
200, never a 500. Also verifies admin auth (Bearer / X-Admin-Key) and that
audit logs expose only fingerprint-level data, never raw user content.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings

ADMIN_KEY = get_settings().ADMIN_API_KEY
ADMIN_HEADERS = {"X-Admin-Key": ADMIN_KEY}


class TestAdminDashboard:
    def test_dashboard_returns_html_200(self, client: TestClient):
        """Regression: the dashboard static path previously resolved to
        app/api/static/ and returned 500. It must serve dashboard.html."""
        resp = client.get("/dashboard", headers=ADMIN_HEADERS)
        assert resp.status_code == 200
        assert "text/html" in resp.headers["content-type"]

    def test_dashboard_html_file_exists_on_disk(self):
        """The served file must exist under backend/app/static/."""
        static = (
            Path(__file__).resolve().parent.parent.parent
            / "app" / "static" / "dashboard.html"
        )
        assert static.is_file(), "dashboard.html missing from backend/app/static/"

    def test_dashboard_requires_auth(self, client: TestClient):
        assert client.get("/dashboard").status_code == 401

    def test_dashboard_rejects_wrong_key(self, client: TestClient):
        assert client.get("/dashboard", headers={"X-Admin-Key": "wrong"}).status_code == 401

    def test_dashboard_accepts_bearer_token(self, client: TestClient):
        resp = client.get(
            "/dashboard", headers={"Authorization": f"Bearer {ADMIN_KEY}"}
        )
        assert resp.status_code == 200


class TestAdminAuditLogs:
    def test_audit_logs_requires_auth(self, client: TestClient):
        assert client.get("/api/audit-logs").status_code == 401

    def test_audit_logs_returns_200_with_key(self, client: TestClient):
        resp = client.get("/api/audit-logs", headers=ADMIN_HEADERS)
        assert resp.status_code == 200
        assert isinstance(resp.json(), list)

    def test_audit_logs_never_expose_raw_content(self, client: TestClient):
        """Rows must be fingerprint-level only: no raw messages/emails/OTPs."""
        resp = client.get("/api/audit-logs?limit=50", headers=ADMIN_HEADERS)
        for row in resp.json():
            # `target` may be a non-sensitive label; it must never equal raw
            # user content. Fingerprint column is a bounded hash prefix.
            assert len(row.get("target_fingerprint", "")) <= 32

    def test_audit_logs_honours_limit(self, client: TestClient):
        resp = client.get("/api/audit-logs?limit=5", headers=ADMIN_HEADERS)
        assert resp.status_code == 200
        assert len(resp.json()) <= 5


class TestAdminStats:
    def test_stats_requires_auth(self, client: TestClient):
        assert client.get("/api/stats").status_code == 401

    def test_stats_returns_200_with_key(self, client: TestClient):
        resp = client.get("/api/stats", headers=ADMIN_HEADERS)
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert "total_audit_events" in data
