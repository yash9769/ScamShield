from __future__ import annotations
"""Regression tests for the ScamShield server (server/main.py).

Run:  cd server && python -m pytest test_server.py -q

These tests exercise the real request/response path via FastAPI's TestClient.
They do not require any API keys: with no keys configured, /analyze falls back
to the deterministic heuristic engine and the OSINT lookups return explicit
"not configured" results, both of which are asserted below.
"""

import io
import zipfile

import pytest
from fastapi.testclient import TestClient

import main
from main import app, heuristic_analyze, extract_strings as extract_strings_blob

# Rate limiting is exercised explicitly in test_rate_limit_blocks_scan_flood
# below; leaving it on globally would throttle the rest of the suite.
main.limiter.enabled = False

client = TestClient(app)


def _make_apk(extra_files: dict | None = None) -> bytes:
    """Build a minimal ZIP that is structurally a valid APK for our analyzer."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        z.writestr("AndroidManifest.xml", "<manifest/>")
        z.writestr("classes.dex", "dex\n035\x00placeholder-bytecode")
        for name, content in (extra_files or {}).items():
            z.writestr(name, content)
    return buf.getvalue()


# ── Health / metadata ────────────────────────────────────────────────────────

def test_health_ok():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "healthy"


def test_root_reports_service_metadata():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json()["service"] == "ScamShield API"


# ── /analyze ─────────────────────────────────────────────────────────────────

def test_analyze_flags_obvious_scam():
    r = client.post("/analyze", json={"text":
        "URGENT! Your bank account is suspended. Verify KYC now at bit.ly/x "
        "and share your OTP immediately!"})
    assert r.status_code == 200
    body = r.json()
    assert body["classification"] == "scam"
    assert body["riskScore"] >= 66
    assert len(body["reasons"]) > 0


def test_analyze_treats_benign_message_as_safe():
    r = client.post("/analyze", json={"text": "Hey, are we still on for lunch tomorrow?"})
    assert r.status_code == 200
    body = r.json()
    assert body["classification"] == "safe"
    assert body["riskScore"] == 0


def test_analyze_rejects_oversized_payload():
    r = client.post("/analyze", json={"text": "a" * 20_000})
    assert r.status_code == 422


def test_analyze_handles_empty_text():
    r = client.post("/analyze", json={"text": "   "})
    assert r.status_code == 200
    assert r.json()["riskScore"] == 0


def test_heuristic_score_is_deterministic():
    text = "Congratulations! You won a lottery prize. Click here: bit.ly/win"
    assert heuristic_analyze(text).riskScore == heuristic_analyze(text).riskScore


def test_heuristic_score_is_bounded():
    # Stacking every trigger must never exceed the 0-100 contract.
    text = ("urgent immediately act now winner lottery prize bank account otp "
            "kyc upi click here verify now bit.ly/x guaranteed risk free " * 20)
    result = heuristic_analyze(text)
    assert 0 <= result.riskScore <= 100


# ── /scan ────────────────────────────────────────────────────────────────────

def test_scan_rejects_non_apk_extension():
    r = client.post("/scan", files={"file": ("notes.txt", b"hello", "text/plain")})
    assert r.status_code == 400


def test_scan_rejects_non_zip_content():
    r = client.post("/scan", files={"file": ("fake.apk", b"definitely not a zip", "application/octet-stream")})
    assert r.status_code == 400


def test_scan_rejects_empty_file():
    r = client.post("/scan", files={"file": ("empty.apk", b"", "application/octet-stream")})
    assert r.status_code == 400


def test_scan_returns_full_report_shape():
    r = client.post("/scan", files={"file": ("app.apk", _make_apk(), "application/vnd.android.package-archive")})
    assert r.status_code == 200
    body = r.json()
    for key in ("scan_mode", "risk", "ai_explanation", "file_info", "androguard", "secrets", "yara", "osint"):
        assert key in body
    assert body["risk"]["level"] in {"LOW", "MEDIUM", "HIGH", "CRITICAL"}
    assert 0 <= body["risk"]["score"] <= 100
    assert len(body["file_info"]["sha256"]) == 64


def test_scan_detects_hardcoded_secrets():
    apk = _make_apk({"classes2.dex": "config AKIAABCDEFGHIJKLMNOP endconfig"})
    r = client.post("/scan", files={"file": ("secrets.apk", apk, "application/octet-stream")})
    assert r.status_code == 200
    assert "aws_access_key" in r.json()["secrets"]["findings"]


def test_scan_is_deterministic_for_same_input():
    apk = _make_apk({"classes2.dex": "some stable content"})
    first = client.post("/scan", files={"file": ("a.apk", apk, "application/octet-stream")}).json()
    second = client.post("/scan", files={"file": ("a.apk", apk, "application/octet-stream")}).json()
    assert first["file_info"]["sha256"] == second["file_info"]["sha256"]
    assert first["risk"]["score"] == second["risk"]["score"]


def test_extract_strings_handles_corrupt_archive(tmp_path):
    bad = tmp_path / "bad.apk"
    bad.write_bytes(b"not a zip at all")
    assert extract_strings_blob(str(bad)) == b""


# ── /osint proxies ───────────────────────────────────────────────────────────

def test_osint_hash_rejects_malformed_hash():
    assert client.get("/osint/hash/nothex").status_code == 400


def test_osint_hash_accepts_valid_sha256():
    r = client.get("/osint/hash/" + "a" * 64)
    assert r.status_code == 200
    assert "note" in r.json()


def test_osint_ip_rejects_non_ip():
    # Guards against SSRF / request injection via the IP path segment.
    assert client.get("/osint/ip/evil.example.com").status_code == 400


def test_osint_ip_accepts_valid_ip():
    assert client.get("/osint/ip/8.8.8.8").status_code == 200


def test_osint_urls_rejects_too_many():
    r = client.post("/osint/urls", json={"urls": ["http://a.com"] * 60})
    assert r.status_code == 422


def test_osint_urls_returns_result_per_url():
    urls = ["http://a.com", "http://b.com"]
    r = client.post("/osint/urls", json={"urls": urls})
    assert r.status_code == 200
    assert len(r.json()["results"]) == len(urls)


def test_unconfigured_osint_never_claims_malicious():
    """A hash that doesn't exist in VT returns malicious=0 and a clear note."""
    # Use all-b hash which won't exist in VT. With a real key it returns 404/0.
    # With no key it says 'not configured'. Either way malicious must be 0.
    body = client.get("/osint/hash/" + "b" * 64).json()
    assert body["malicious"] == 0
    # Note must contain EITHER a "not configured" message OR a "not found" message
    note = body["note"].lower()
    assert "not configured" in note or "not found" in note or "new or unknown" in note


# ── Caching ──────────────────────────────────────────────────────────────────

def test_repeat_scan_is_served_from_cache():
    apk = _make_apk({"classes2.dex": "cache probe content"})
    first = client.post("/scan", files={"file": ("c.apk", apk, "application/octet-stream")}).json()
    second = client.post("/scan", files={"file": ("c.apk", apk, "application/octet-stream")}).json()
    assert first["cached"] is False
    assert second["cached"] is True
    # A cached report must be identical apart from the flag itself.
    assert first["risk"] == second["risk"]
    assert first["file_info"]["sha256"] == second["file_info"]["sha256"]


def test_different_apks_do_not_share_cache_entries():
    a = _make_apk({"classes2.dex": "alpha"})
    b = _make_apk({"classes2.dex": "beta"})
    ra = client.post("/scan", files={"file": ("a.apk", a, "application/octet-stream")}).json()
    rb = client.post("/scan", files={"file": ("b.apk", b, "application/octet-stream")}).json()
    assert ra["file_info"]["sha256"] != rb["file_info"]["sha256"]
    assert rb["cached"] is False


# ── Rate limiting ────────────────────────────────────────────────────────────

def test_rate_limit_blocks_scan_flood():
    """The /scan limit must actually reject a flood once exceeded."""
    main.limiter.enabled = True
    main.limiter.reset()
    try:
        apk = _make_apk({"classes2.dex": "flood probe"})
        codes = []
        for i in range(13):
            # Vary content so the cache does not short-circuit the work.
            payload = _make_apk({"classes2.dex": f"flood probe {i}"})
            r = client.post("/scan", files={"file": (f"f{i}.apk", payload, "application/octet-stream")})
            codes.append(r.status_code)
        assert 429 in codes, f"expected throttling, got {codes}"
        assert codes[0] == 200
    finally:
        main.limiter.enabled = False
        main.limiter.reset()


# ── Breach checks ────────────────────────────────────────────────────────────
from unittest.mock import AsyncMock, patch
import httpx

@patch("httpx.AsyncClient.get")
def test_breach_no_exposure(mock_get):
    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.json = lambda: {
        "BreachMetrics": None,
        "ExposedBreaches": None
    }
    mock_get.return_value = mock_response

    r = client.get("/breach?email=safe@example.com")
    assert r.status_code == 200
    body = r.json()
    assert body["email"] == "safe@example.com"
    assert body["exposed"] is False
    assert body["breachCount"] == 0
    assert body["breaches"] == []

@patch("httpx.AsyncClient.get")
def test_breach_exposed(mock_get):
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

    r = client.get("/breach?email=breached@example.com")
    assert r.status_code == 200
    body = r.json()
    assert body["email"] == "breached@example.com"
    assert body["exposed"] is True
    assert body["breachCount"] == 1
    assert body["breaches"][0]["name"] == "Paidwork"
    assert body["breaches"][0]["domain"] == "paidwork.com"
    assert body["breaches"][0]["date"] == "2026-01-01"
    assert body["breaches"][0]["dataClasses"] == ["Email addresses", "Passwords"]

def test_breach_invalid_email():
    r = client.get("/breach?email=invalid-email")
    assert r.status_code == 400

@patch("httpx.AsyncClient.get")
def test_breach_timeout(mock_get):
    mock_get.side_effect = httpx.TimeoutException("Timeout")
    r = client.get("/breach?email=test@example.com")
    assert r.status_code == 504

@patch("httpx.AsyncClient.get")
def test_breach_rate_limit(mock_get):
    mock_response = AsyncMock()
    mock_response.status_code = 429
    mock_get.return_value = mock_response
    r = client.get("/breach?email=test@example.com")
    assert r.status_code == 429

@patch("httpx.AsyncClient.get")
def test_breach_api_error(mock_get):
    mock_response = AsyncMock()
    mock_response.status_code = 500
    mock_get.return_value = mock_response
    r = client.get("/breach?email=test@example.com")
    assert r.status_code == 502

@patch("httpx.AsyncClient.get")
def test_breach_malformed(mock_get):
    mock_response = AsyncMock()
    mock_response.status_code = 200
    def raise_val_error():
        raise ValueError("JSON error")
    mock_response.json = raise_val_error
    mock_get.return_value = mock_response
    r = client.get("/breach?email=test@example.com")
    assert r.status_code == 502

