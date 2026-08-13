"""
Lightweight test runner to verify XposedOrNotService unit tests.
Bypasses pytest's dependency on plugins and sqlalchemy conftest imports.
"""
import asyncio
import httpx
from unittest.mock import AsyncMock, patch
from fastapi import HTTPException

from app.services.xposedornot import XposedOrNotService

async def run_tests():
    xon_service = XposedOrNotService()

    # 1. test_validate_email_valid
    assert xon_service.validate_email("test@example.com") is True
    assert xon_service.validate_email("user.name+tag@domain.co.uk") is True
    print("[OK] test_validate_email_valid passed")

    # 2. test_validate_email_invalid
    assert xon_service.validate_email("plainaddress") is False
    assert xon_service.validate_email("@missinguser.com") is False
    assert xon_service.validate_email("user@missingtld") is False
    print("[OK] test_validate_email_invalid passed")

    # 3. test_check_email_exposure_no_breaches
    with patch("httpx.AsyncClient.get") as mock_get:
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
        print("[OK] test_check_email_exposure_no_breaches passed")

    # 4. test_check_email_exposure_with_breaches
    with patch("httpx.AsyncClient.get") as mock_get:
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
        print("[OK] test_check_email_exposure_with_breaches passed")

    # 5. test_check_email_exposure_invalid_email
    try:
        await xon_service.check_email_exposure("invalid-email")
        assert False, "Expected HTTPException"
    except HTTPException as exc:
        assert exc.status_code == 400
        print("[OK] test_check_email_exposure_invalid_email passed")

    # 6. test_check_email_exposure_timeout
    with patch("httpx.AsyncClient.get") as mock_get:
        mock_get.side_effect = httpx.TimeoutException("Timeout")
        try:
            await xon_service.check_email_exposure("test@example.com")
            assert False, "Expected HTTPException"
        except HTTPException as exc:
            assert exc.status_code == 504
            print("[OK] test_check_email_exposure_timeout passed")

    # 7. test_check_email_exposure_429
    with patch("httpx.AsyncClient.get") as mock_get:
        mock_response = AsyncMock()
        mock_response.status_code = 429
        mock_get.return_value = mock_response
        try:
            await xon_service.check_email_exposure("test@example.com")
            assert False, "Expected HTTPException"
        except HTTPException as exc:
            assert exc.status_code == 429
            print("[OK] test_check_email_exposure_429 passed")

    # 8. test_check_email_exposure_500
    with patch("httpx.AsyncClient.get") as mock_get:
        mock_response = AsyncMock()
        mock_response.status_code = 500
        mock_get.return_value = mock_response
        try:
            await xon_service.check_email_exposure("test@example.com")
            assert False, "Expected HTTPException"
        except HTTPException as exc:
            assert exc.status_code == 502
            print("[OK] test_check_email_exposure_500 passed")

    # 9. test_check_email_exposure_malformed_json
    with patch("httpx.AsyncClient.get") as mock_get:
        mock_response = AsyncMock()
        mock_response.status_code = 200
        def raise_val_error():
            raise ValueError("JSON decode error")
        mock_response.json = raise_val_error
        mock_get.return_value = mock_response
        try:
            await xon_service.check_email_exposure("test@example.com")
            assert False, "Expected HTTPException"
        except HTTPException as exc:
            assert exc.status_code == 502
            print("[OK] test_check_email_exposure_malformed_json passed")

    print("\nALL 9 UNIT TESTS PASSED SUCCESSFULLY!")

if __name__ == "__main__":
    asyncio.run(run_tests())
