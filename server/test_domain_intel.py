from __future__ import annotations
"""Tests for the free, keyless domain-intelligence feature (crt.sh + RDAP).

External calls are mocked — hitting crt.sh/rdap.org from CI would be slow,
flaky, and an unnecessary load on free public services. Run:
  cd server && python -m pytest test_domain_intel.py -q
"""

from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

import main
from main import app, crtsh_domain_check, rdap_domain_age, domain_intel

main.limiter.enabled = False
client = TestClient(app)


def _resp(status_code=200, json_data=None, text="[]"):
    r = AsyncMock()
    r.status_code = status_code
    r.json = lambda: json_data if json_data is not None else []
    r.text = text
    return r


# ── crt.sh ────────────────────────────────────────────────────────────────────

@patch("httpx.AsyncClient.get")
@pytest.mark.asyncio
async def test_crtsh_no_certificates_found(mock_get):
    mock_get.return_value = _resp(200, [], text="[]")
    result = await crtsh_domain_check("brand-new-scam-domain.tk")
    assert result["checked"] is True
    assert result["cert_count"] == 0
    assert result["first_seen_days_ago"] is None


@patch("httpx.AsyncClient.get")
@pytest.mark.asyncio
async def test_crtsh_computes_age_from_oldest_cert(mock_get):
    mock_get.return_value = _resp(200, [
        {"not_before": "2020-01-01T00:00:00"},
        {"not_before": "2023-06-01T00:00:00"},
    ], text="not empty")
    result = await crtsh_domain_check("google.com")
    assert result["checked"] is True
    assert result["cert_count"] == 2
    assert result["first_seen_days_ago"] is not None
    assert result["first_seen_days_ago"] > 365 * 3  # oldest cert is from 2020


@patch("httpx.AsyncClient.get", side_effect=Exception("network error"))
@pytest.mark.asyncio
async def test_crtsh_handles_network_failure(mock_get):
    result = await crtsh_domain_check("example.com")
    assert result["checked"] is False
    assert result["cert_count"] == 0


# ── RDAP ──────────────────────────────────────────────────────────────────────

@patch("httpx.AsyncClient.get")
@pytest.mark.asyncio
async def test_rdap_extracts_registration_age(mock_get):
    mock_get.return_value = _resp(200, {
        "events": [{"eventAction": "registration", "eventDate": "1997-09-15T00:00:00Z"}]
    })
    result = await rdap_domain_age("google.com")
    assert result["checked"] is True
    assert result["registered_days_ago"] > 365 * 20


@patch("httpx.AsyncClient.get")
@pytest.mark.asyncio
async def test_rdap_unavailable_for_unknown_tld(mock_get):
    mock_get.return_value = _resp(404, {})
    result = await rdap_domain_age("nonexistent.invalidtld")
    assert result["checked"] is False
    assert result["registered_days_ago"] is None


@patch("httpx.AsyncClient.get", side_effect=Exception("timeout"))
@pytest.mark.asyncio
async def test_rdap_handles_network_failure(mock_get):
    result = await rdap_domain_age("example.com")
    assert result["checked"] is False


# ── Combined domain_intel() ────────────────────────────────────────────────────

@patch("main.rdap_domain_age", new_callable=AsyncMock)
@patch("main.crtsh_domain_check", new_callable=AsyncMock)
@pytest.mark.asyncio
async def test_domain_intel_flags_brand_new_domain(mock_cert, mock_rdap):
    mock_cert.return_value = {"checked": True, "cert_count": 0, "first_seen_days_ago": None, "note": "none"}
    mock_rdap.return_value = {"checked": True, "registered_days_ago": 3, "note": "recent"}
    result = await domain_intel("just-registered-phish.tk")
    assert result["newly_registered_or_unproven"] is True


@patch("main.rdap_domain_age", new_callable=AsyncMock)
@patch("main.crtsh_domain_check", new_callable=AsyncMock)
@pytest.mark.asyncio
async def test_domain_intel_trusts_established_domain(mock_cert, mock_rdap):
    mock_cert.return_value = {"checked": True, "cert_count": 40, "first_seen_days_ago": 4000, "note": "many"}
    mock_rdap.return_value = {"checked": True, "registered_days_ago": 9000, "note": "old"}
    result = await domain_intel("google.com")
    assert result["newly_registered_or_unproven"] is False


# ── GET /osint/domain/{domain} ────────────────────────────────────────────────

def test_osint_domain_rejects_invalid_format():
    r = client.get("/osint/domain/not a domain!!")
    assert r.status_code == 400


def test_osint_domain_rejects_bare_ip():
    r = client.get("/osint/domain/8.8.8.8")
    assert r.status_code == 400


@patch("main.rdap_domain_age", new_callable=AsyncMock)
@patch("main.crtsh_domain_check", new_callable=AsyncMock)
def test_osint_domain_accepts_valid_domain(mock_cert, mock_rdap):
    mock_cert.return_value = {"checked": True, "cert_count": 5, "first_seen_days_ago": 900, "note": "ok"}
    mock_rdap.return_value = {"checked": True, "registered_days_ago": 1000, "note": "ok"}
    r = client.get("/osint/domain/example.com")
    assert r.status_code == 200
    body = r.json()
    assert body["domain"] == "example.com"
    assert "certificate_transparency" in body
    assert "rdap" in body
    assert body["newly_registered_or_unproven"] is False


def test_root_reports_domain_intel_always_available():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json()["domain_intel"] is True
