"""
backend/tests/unit/test_xposedornot.py
Unit tests for XposedOrNotService.
"""

from __future__ import annotations

import httpx
import pytest
from unittest.mock import AsyncMock, patch
from fastapi import HTTPException

from app.services.xposedornot import XposedOrNotService

@pytest.fixture
def xon_service() -> XposedOrNotService:
    return XposedOrNotService()

class TestXposedOrNotService:
    def test_validate_email_valid(self, xon_service: XposedOrNotService):
        assert xon_service.validate_email("test@example.com") is True
        assert xon_service.validate_email("user.name+tag@domain.co.uk") is True

    def test_validate_email_invalid(self, xon_service: XposedOrNotService):
        assert xon_service.validate_email("plainaddress") is False
        assert xon_service.validate_email("@missinguser.com") is False
        assert xon_service.validate_email("user@missingtld") is False

    @patch("httpx.AsyncClient.get")
    @pytest.mark.asyncio
    async def test_check_email_exposure_no_breaches(self, mock_get, xon_service: XposedOrNotService):
        mock_response = AsyncMock()
        mock_response.status_code = 200
        mock_response.json = lambda: {
            "BreachMetrics": None,
            "BreachesSummary": {"site": ""},
            "ExposedBreaches": None,
            "ExposedPastes": None,
            "PasteMetrics": None,
            "PastesSummary": {"cnt": 0, "domain": "", "tmpstmp": ""}
        }
        mock_get.return_value = mock_response

        res = await xon_service.check_email_exposure("safe@example.com")
        assert res["exposed"] is False
        assert res["breachCount"] == 0
        assert len(res["breaches"]) == 0

    @patch("httpx.AsyncClient.get")
    @pytest.mark.asyncio
    async def test_check_email_exposure_with_breaches(self, mock_get, xon_service: XposedOrNotService):
        mock_response = AsyncMock()
        mock_response.status_code = 200
        mock_response.json = lambda: {
            "ExposedBreaches": {
                "breaches_details": [
                    {
                        "breach": "Paidwork",
                        "domain": "paidwork.com",
                        "xposed_data": "Email addresses;Passwords",
                        "xposed_date": "2026"
                    }
                ]
            }
        }
        mock_get.return_value = mock_response

        res = await xon_service.check_email_exposure("breached@example.com")
        assert res["exposed"] is True
        assert res["breachCount"] == 1
        assert len(res["breaches"]) == 1
        assert res["breaches"][0]["name"] == "Paidwork"
        assert res["breaches"][0]["domain"] == "paidwork.com"
        assert res["breaches"][0]["date"] == "2026-01-01"
        assert res["breaches"][0]["dataClasses"] == ["Email addresses", "Passwords"]

    @pytest.mark.asyncio
    async def test_check_email_exposure_invalid_email(self, xon_service: XposedOrNotService):
        with pytest.raises(HTTPException) as excinfo:
            await xon_service.check_email_exposure("invalid-email")
        assert excinfo.value.status_code == 400

    @patch("httpx.AsyncClient.get")
    @pytest.mark.asyncio
    async def test_check_email_exposure_timeout(self, mock_get, xon_service: XposedOrNotService):
        mock_get.side_effect = httpx.TimeoutException("Timeout")
        with pytest.raises(HTTPException) as excinfo:
            await xon_service.check_email_exposure("test@example.com")
        assert excinfo.value.status_code == 504

    @patch("httpx.AsyncClient.get")
    @pytest.mark.asyncio
    async def test_check_email_exposure_429(self, mock_get, xon_service: XposedOrNotService):
        mock_response = AsyncMock()
        mock_response.status_code = 429
        mock_get.return_value = mock_response
        with pytest.raises(HTTPException) as excinfo:
            await xon_service.check_email_exposure("test@example.com")
        assert excinfo.value.status_code == 429

    @patch("httpx.AsyncClient.get")
    @pytest.mark.asyncio
    async def test_check_email_exposure_500(self, mock_get, xon_service: XposedOrNotService):
        mock_response = AsyncMock()
        mock_response.status_code = 500
        mock_get.return_value = mock_response
        with pytest.raises(HTTPException) as excinfo:
            await xon_service.check_email_exposure("test@example.com")
        assert excinfo.value.status_code == 502

    @patch("httpx.AsyncClient.get")
    @pytest.mark.asyncio
    async def test_check_email_exposure_malformed_json(self, mock_get, xon_service: XposedOrNotService):
        mock_response = AsyncMock()
        mock_response.status_code = 200
        def raise_val_error():
            raise ValueError("JSON decode error")
        mock_response.json = raise_val_error
        mock_get.return_value = mock_response
        with pytest.raises(HTTPException) as excinfo:
            await xon_service.check_email_exposure("test@example.com")
        assert excinfo.value.status_code == 502
