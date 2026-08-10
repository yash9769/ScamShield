import io
import zipfile
import sqlite3
import httpx
import pytest

BASE_URL = "http://127.0.0.1:8000"
ADMIN_KEY = "scamshield_admin_sec_key_2026"

def test_phase_1_and_2_dashboard_authorization():
    print("\n--- PHASE 1 & 2: Testing SOC Dashboard Authorization & Security Gates ---")
    
    # DASH-SEC-001: Unauthenticated GET /dashboard
    r1 = httpx.get(f"{BASE_URL}/dashboard")
    assert r1.status_code == 401, f"Expected 401, got {r1.status_code}"
    print("  └─ DASH-SEC-001 Passed: Unauthenticated /dashboard rejected with HTTP 401.")

    # DASH-SEC-002: Unauthenticated GET /api/audit-logs
    r2 = httpx.get(f"{BASE_URL}/api/audit-logs")
    assert r2.status_code == 401, f"Expected 401, got {r2.status_code}"
    print("  └─ DASH-SEC-002 Passed: Unauthenticated /api/audit-logs rejected with HTTP 401.")

    # DASH-SEC-003: Invalid key token attempt
    r3 = httpx.get(f"{BASE_URL}/api/audit-logs", headers={"X-Admin-Key": "invalid_admin_secret"})
    assert r3.status_code == 401, f"Expected 401, got {r3.status_code}"
    print("  └─ DASH-SEC-003 Passed: Invalid token rejected with HTTP 401.")

    # DASH-SEC-004: Query parameter ?key=... credential MUST BE REJECTED (HTTP 401)
    r4_query = httpx.get(f"{BASE_URL}/dashboard?key={ADMIN_KEY}")
    assert r4_query.status_code == 401, f"Expected 401 for query credential, got {r4_query.status_code}"
    print("  └─ DASH-SEC-004 Passed: Query-string credential ?key=... correctly rejected (HTTP 401).")

    # DASH-SEC-005: Authenticated Administrator via X-Admin-Key header
    r4_header = httpx.get(f"{BASE_URL}/dashboard", headers={"X-Admin-Key": ADMIN_KEY})
    assert r4_header.status_code == 200, f"Expected 200, got {r4_header.status_code}"
    assert "SCAMSHIELD" in r4_header.text
    print("  └─ DASH-SEC-005 Passed: Authenticated access to /dashboard via X-Admin-Key header succeeded (HTTP 200).")

    # DASH-SEC-006: Direct server-side API authorization check via Bearer header
    r5 = httpx.get(f"{BASE_URL}/api/audit-logs", headers={"Authorization": f"Bearer {ADMIN_KEY}"})
    assert r5.status_code == 200, f"Expected 200, got {r5.status_code}"
    print("  └─ DASH-SEC-006 Passed: Server-side authorization check via Bearer header succeeded.")

def test_phase_3_and_4_audit_log_hardening_and_redaction():
    print("\n--- PHASE 3 & 4: Audit Log Data Redaction & Server-Side Bound Testing ---")
    
    # Trigger event with API Key in content
    sensitive_target = "Analysis of API key: AIzaSyDUMMYFAKEKEYFORTESTS0000000000000000 in string"
    httpx.post(f"{BASE_URL}/analyze", json={"text": sensitive_target})
    
    # Fetch logs with admin auth
    r = httpx.get(f"{BASE_URL}/api/audit-logs?limit=5", headers={"X-Admin-Key": ADMIN_KEY})
    assert r.status_code == 200
    logs = r.json()
    
    # Verify Secret Redaction (Phase 3)
    redacted_found = any("[REDACTED_SECRET]" in l.get("target", "") for l in logs)
    print("  └─ Phase 3 Secret Redaction Verified:", redacted_found)
    assert redacted_found, "Audit logs failed to redact sensitive API keys!"

    # Test Server-Side Limit Bounding (Phase 4)
    # Excess limit (100,000) should be clamped to max 100
    r_excess = httpx.get(f"{BASE_URL}/api/audit-logs?limit=100000", headers={"X-Admin-Key": ADMIN_KEY})
    assert r_excess.status_code == 200
    assert len(r_excess.json()) <= 100
    print("  └─ Phase 4 Bound Testing Passed: Excess limit 100,000 clamped to <= 100 rows.")

def test_phase_5_api_rate_limiting():
    print("\n--- PHASE 5: Testing API Rate Limiting Thresholds ---")
    
    # POST /analyze limit is configured at 60/minute
    allowed_count = 0
    blocked_429 = False
    
    for _ in range(70):
        r = httpx.post(f"{BASE_URL}/analyze", json={"text": "Rate limit verification benchmark request"})
        if r.status_code == 200:
            allowed_count += 1
        elif r.status_code == 429:
            blocked_429 = True
            break
            
    print(f"  └─ Observed Requests Allowed: {allowed_count}, HTTP 429 Blocked: {blocked_429}")
    assert blocked_429, "Rate limiter failed to enforce HTTP 429 on excessive requests!"
    print("  └─ Phase 5 Rate Limiting Enforcement Verified OK.")

def test_phase_7_apk_zip_bomb_prevention():
    print("\n--- PHASE 7: APK Zip Bomb & Extraction Safety Audit ---")
    
    # Create malicious ZIP with 10,005 dummy files
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("AndroidManifest.xml", b"<manifest package='com.zipbomb.test'></manifest>")
        for i in range(10005):
            zf.writestr(f"res/drawable/file_{i}.png", b"0")
            
    r = httpx.post(f"{BASE_URL}/scan", files={"file": ("zipbomb.apk", buf.getvalue(), "application/vnd.android.package-archive")})
    assert r.status_code == 200
    res = r.json()
    print("  └─ Zip Bomb Scan Response:", res.get("ai_explanation"))
    assert res.get("scan_mode") == "server"
    print("  └─ Phase 7 Zip Bomb & Extraction Safety Verified OK.")

if __name__ == "__main__":
    test_phase_1_and_2_dashboard_authorization()
    test_phase_3_and_4_audit_log_hardening_and_redaction()
    test_phase_5_api_rate_limiting()
    test_phase_7_apk_zip_bomb_prevention()
    print("\n=================================================================")
    print("      ALL PRODUCTION SECURITY REMEDIATION TESTS PASSED OK        ")
    print("=================================================================")
