import io
import zipfile
import sqlite3
import httpx
import pytest

BASE_URL = "http://127.0.0.1:8000"

ADMIN_KEY = "scamshield_admin_sec_key_2026"

def test_soc_dashboard_and_audit_pipeline():
    print("\n--- 1. Testing SOC Dashboard & Audit Logging Pipeline ---")
    
    # 1. Clear or check audit logs before
    r = httpx.get(f"{BASE_URL}/api/audit-logs", headers={"X-Admin-Key": ADMIN_KEY})
    assert r.status_code == 200, f"Expected 200, got {r.status_code}"
    initial_logs = r.json()
    initial_count = len(initial_logs)
    
    # 2. Trigger known unique security events
    event_1 = "TEST_EVENT_001_PHISHING_LINK_CHECK"
    event_2 = "TEST_EVENT_002_MALICIOUS_APK_UPLOAD"
    
    r1 = httpx.post(f"{BASE_URL}/analyze", json={"text": event_1})
    assert r1.status_code == 200
    
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("AndroidManifest.xml", b"<manifest package='com.test.event002'></manifest>")
    r2 = httpx.post(f"{BASE_URL}/scan", files={"file": ("test002.apk", buf.getvalue(), "application/vnd.android.package-archive")})
    assert r2.status_code == 200
    
    # 3. Verify audit database directly
    conn = sqlite3.connect("server_audit.db")
    cur = conn.cursor()
    cur.execute("SELECT target, risk_score, risk_level FROM audit_logs ORDER BY id DESC LIMIT 2")
    db_rows = cur.fetchall()
    conn.close()
    
    assert len(db_rows) >= 2, "Database did not insert events!"
    print("  └─ DB Audit Rows Verified:", db_rows)
    
    # 4. Verify API /api/audit-logs
    r_api = httpx.get(f"{BASE_URL}/api/audit-logs?limit=100", headers={"X-Admin-Key": ADMIN_KEY})
    assert r_api.status_code == 200
    api_logs = r_api.json()
    assert len(api_logs) >= initial_count + 2 or len(api_logs) == 100, "API audit log count mismatch!"
    print("  └─ API Audit Log Stream Verified OK.")
    
    # 5. Verify /dashboard HTML loading
    r_dash = httpx.get(f"{BASE_URL}/dashboard", headers={"X-Admin-Key": ADMIN_KEY})
    assert r_dash.status_code == 200
    assert "SCAMSHIELD" in r_dash.text
    print("  └─ SOC Dashboard Portal HTML Verified OK.")

def test_yara_rule_matching():
    print("\n--- 2. Testing YARA Rule Matching Against Malicious DEX Binary ---")
    
    # Create APK with Anubis banking trojan signature strings
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("AndroidManifest.xml", b"<manifest package='com.malware.anubis'></manifest>")
        # Anubis YARA rule requires: "Anubis", "android.intent.action.PACKAGE_ADDED", "android.app.action.DEVICE_ADMIN_ENABLED"
        malware_dex = b"Anubis string in DEX android.intent.action.PACKAGE_ADDED and android.app.action.DEVICE_ADMIN_ENABLED"
        zf.writestr("classes.dex", malware_dex)
        
    r = httpx.post(f"{BASE_URL}/scan", files={"file": ("anubis_trojan.apk", buf.getvalue(), "application/vnd.android.package-archive")})
    assert r.status_code == 200
    data = r.json()
    
    yara_matches = data.get("yara", {}).get("matches", [])
    print("  └─ YARA Hits Detected:", yara_matches)
    assert len(yara_matches) > 0, "YARA rule failed to detect Anubis trojan signatures!"
    assert "Anubis" in yara_matches, "Anubis rule was not matched!"
    print("  └─ YARA Signature Detection Verified OK!")

def test_androguard_manifest_parser():
    print("\n--- 3. Testing Androguard Manifest Parser ---")
    
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("AndroidManifest.xml", b"<manifest package='com.test.androguard'></manifest>")
    
    r = httpx.post(f"{BASE_URL}/scan", files={"file": ("androguard_test.apk", buf.getvalue(), "application/vnd.android.package-archive")})
    assert r.status_code == 200
    data = r.json()
    androguard_info = data.get("androguard", {})
    print("  └─ Androguard Output Status:", androguard_info.get("status"))
    assert androguard_info.get("status") in ("success", "OK"), "Androguard failed execution!"

def test_virustotal_eicar_and_safe_browsing():
    print("\n--- 4. Testing VirusTotal & Google Safe Browsing Live APIs ---")
    
    # VirusTotal EICAR malware hash
    eicar_hash = "131f95c51cc819465fa1797f6ccacf9d494aaaff46fa3eac73ae63ffbdfd8267"
    r_vt = httpx.get(f"{BASE_URL}/osint/hash/{eicar_hash}")
    assert r_vt.status_code == 200
    vt_data = r_vt.json()
    print("  └─ VirusTotal EICAR Detection Count:", vt_data.get("malicious"))
    assert vt_data.get("malicious", 0) > 50, "VirusTotal failed to identify EICAR malware hash!"
    
    # Google Safe Browsing Phishing URL
    phishing_url = "http://testsafebrowsing.appspot.com/s/phishing.html"
    r_gsb = httpx.post(f"{BASE_URL}/osint/urls", json={"urls": [phishing_url]})
    assert r_gsb.status_code == 200
    gsb_results = r_gsb.json().get("results", [])
    print("  └─ Google Safe Browsing Result:", gsb_results)
    assert any(res.get("malicious") is True for res in gsb_results), "Google Safe Browsing failed to flag phishing URL!"

def test_batch_apk_processing():
    print("\n--- 5. Testing Batch APK Parallel Scan & Resiliency ---")
    
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("AndroidManifest.xml", b"<manifest package='com.batch.one'></manifest>")
    valid_apk = buf.getvalue()
    invalid_file = b"Not an APK file content"
    
    files = [
        ("files", ("valid_1.apk", valid_apk, "application/vnd.android.package-archive")),
        ("files", ("corrupt.apk", invalid_file, "application/vnd.android.package-archive")),
        ("files", ("valid_2.apk", valid_apk, "application/vnd.android.package-archive")),
    ]
    
    r = httpx.post(f"{BASE_URL}/scan-batch", files=files)
    assert r.status_code == 200
    batch_res = r.json()
    print("  └─ Batch Scan Summary:", batch_res.get("total_files"), "file(s) processed.")
    results = batch_res.get("results", [])
    assert len(results) == 3, "Batch response file count mismatch!"
    assert results[0]["status"] == "scanned", "Valid APK 1 failed in batch!"
    assert results[1]["status"] == "skipped", "Corrupt file was not skipped properly!"
    assert results[2]["status"] == "scanned", "Valid APK 2 failed in batch!"
    print("  └─ Batch Resiliency & Mapping Verified OK!")

if __name__ == "__main__":
    test_soc_dashboard_and_audit_pipeline()
    test_yara_rule_matching()
    test_androguard_manifest_parser()
    test_virustotal_eicar_and_safe_browsing()
    test_batch_apk_processing()
    print("\n=================================================================")
    print("     ALL ADVERSARIAL QA BEHAVIORAL VERIFICATION TESTS PASSED     ")
    print("=================================================================")
