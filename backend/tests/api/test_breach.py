"""
backend/tests/api/test_breach.py
API integration/endpoint tests for GET /breach.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, patch
import pytest
from fastapi.testclient import TestClient


class TestBreachEndpoint:
    @patch("app.services.xposedornot.XposedOrNotService.check_email_exposure")
    def test_breach_endpoint_success(self, mock_check, client: TestClient):
        mock_check.return_value = {
            "email": "test@example.com",
            "exposed": False,
            "breachCount": 0,
            "breaches": [],
            "source": "XposedOrNot",
            "checkedAt": "2026-08-09T19:25:35.000000Z"
        }

        resp = client.get("/breach?email=test@example.com")
        assert resp.status_code == 200
        data = resp.json()
        assert data["email"] == "test@example.com"
        assert data["exposed"] is False
        assert data["breachCount"] == 0
        assert data["breaches"] == []

    @patch("app.services.xposedornot.XposedOrNotService.check_email_exposure")
    def test_breach_endpoint_with_breaches(self, mock_check, client: TestClient):
        mock_check.return_value = {
            "email": "breached@example.com",
            "exposed": True,
            "breachCount": 1,
            "breaches": [
                {
                    "name": "Paidwork",
                    "domain": "paidwork.com",
                    "date": "2026-01-01",
                    "dataClasses": ["Email addresses", "Passwords"]
                }
            ],
            "source": "XposedOrNot",
            "checkedAt": "2026-08-09T19:25:35.000000Z"
        }

        resp = client.get("/breach?email=breached@example.com")
        assert resp.status_code == 200
        data = resp.json()
        assert data["email"] == "breached@example.com"
        assert data["exposed"] is True
        assert data["breachCount"] == 1
        assert len(data["breaches"]) == 1
        assert data["breaches"][0]["name"] == "Paidwork"

    def test_breach_endpoint_invalid_email(self, client: TestClient):
        resp = client.get("/breach?email=invalid-email")
        assert resp.status_code == 400

    def test_breach_endpoint_missing_email(self, client: TestClient):
        resp = client.get("/breach")
        assert resp.status_code == 422
