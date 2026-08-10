import io
import zipfile
import httpx

BASE_URL = "http://127.0.0.1:8000"

def test_root():
    print("\n[1] Testing GET / (System Info)")
    r = httpx.get(f"{BASE_URL}/")
    print(f"    Status: {r.status_code}")
    print(f"    Payload: {r.json()}")
    assert r.status_code == 200

def test_health():
    print("\n[2] Testing GET /health")
    r = httpx.get(f"{BASE_URL}/health")
    print(f"    Status: {r.status_code}")
    print(f"    Payload: {r.json()}")
    assert r.status_code == 200

def test_stats():
    print("\n[3] Testing GET /stats")
    r = httpx.get(f"{BASE_URL}/stats")
    print(f"    Status: {r.status_code}")
    print(f"    Payload: {r.json()}")
    assert r.status_code == 200

def test_analyze_text():
    print("\n[4] Testing POST /analyze (Text Scam Detection)")
    payload = {"text": "URGENT: Your bank account is locked! Verify now at http://bit.ly/fake-bank"}
    r = httpx.post(f"{BASE_URL}/analyze", json=payload)
    print(f"    Status: {r.status_code}")
    data = r.json()
    print(f"    Classification: {data.get('classification')} (Risk Score: {data.get('riskScore')}/100)")
    print(f"    Summary: {data.get('summary')}")
    assert r.status_code == 200

def test_osint_hash():
    print("\n[5] Testing GET /osint/hash/{file_hash} (VirusTotal lookup)")
    # Test SHA-256 hash (EICAR test file hash)
    eicar_hash = "131f95c51cc819465fa1797f6ccacf9d494aaaff46fa3eac73ae63ffbdfd8267"
    r = httpx.get(f"{BASE_URL}/osint/hash/{eicar_hash}")
    print(f"    Status: {r.status_code}")
    print(f"    VirusTotal Response: {r.json()}")
    assert r.status_code == 200

def test_osint_urls():
    print("\n[6] Testing POST /osint/urls (Google Safe Browsing lookup)")
    payload = {"urls": ["http://testsafebrowsing.appspot.com/s/phishing.html", "https://google.com"]}
    r = httpx.post(f"{BASE_URL}/osint/urls", json=payload)
    print(f"    Status: {r.status_code}")
    print(f"    Safe Browsing Response: {r.json()}")
    assert r.status_code == 200

def test_osint_ip():
    print("\n[7] Testing GET /osint/ip/{ip} (AbuseIPDB IP lookup)")
    test_ip = "8.8.8.8"
    r = httpx.get(f"{BASE_URL}/osint/ip/{test_ip}")
    print(f"    Status: {r.status_code}")
    print(f"    AbuseIPDB Response: {r.json()}")
    assert r.status_code == 200

def test_scan_apk():
    print("\n[8] Testing POST /scan (APK Full Static Analysis)")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("AndroidManifest.xml", b"<manifest package='com.security.testapp'></manifest>")
        zf.writestr("classes.dex", b"https://bit.ly/suspicious-link-check AIzaSyDummyKeyForTesting1234567890")
    apk_bytes = buf.getvalue()
    
    r = httpx.post(
        f"{BASE_URL}/scan",
        files={"file": ("test_app.apk", apk_bytes, "application/vnd.android.package-archive")},
        timeout=15.0
    )
    print(f"    Status: {r.status_code}")
    data = r.json()
    print(f"    Risk Level: {data['risk']['level']} ({data['risk']['score']}/100)")
    print(f"    VirusTotal Check: {data['osint']['virustotal']}")
    print(f"    Safe Browsing Check: {data['osint']['safe_browsing']}")
    print(f"    AI Explanation: {data['ai_explanation']}")
    assert r.status_code == 200

def test_analyze_voice():
    print("\n[9] Testing POST /analyze-voice (Voice Audio Note Analysis)")
    fake_audio = b"RIFF....WAVEfmt ....data...." # Fake wav bytes
    r = httpx.post(f"{BASE_URL}/analyze-voice", files={"file": ("sample_voice.wav", fake_audio, "audio/wav")})
    print(f"    Status: {r.status_code}")
    data = r.json()
    print(f"    Voice Analysis Result: {data.get('classification')} (Risk Score: {data.get('riskScore')}/100)")
    assert r.status_code == 200

def test_analyze_image():
    print("\n[10] Testing POST /analyze-image (Screenshot OCR Analysis)")
    fake_image = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR...." # Fake png bytes
    r = httpx.post(f"{BASE_URL}/analyze-image", files={"file": ("screenshot.png", fake_image, "image/png")})
    print(f"    Status: {r.status_code}")
    data = r.json()
    print(f"    Image OCR Result: {data.get('classification')} (Risk Score: {data.get('riskScore')}/100)")
    assert r.status_code == 200

ADMIN_KEY = "scamshield_admin_sec_key_2026"

def test_dashboard():
    print("\n[11] Testing GET /dashboard (Web SOC Threat Dashboard Portal)")
    r = httpx.get(f"{BASE_URL}/dashboard?key={ADMIN_KEY}")
    print(f"    Status: {r.status_code}")
    assert r.status_code == 200 and "SCAMSHIELD" in r.text

def test_audit_logs():
    print("\n[12] Testing GET /api/audit-logs (Security Audit Log Stream)")
    r = httpx.get(f"{BASE_URL}/api/audit-logs", headers={"X-Admin-Key": ADMIN_KEY})
    print(f"    Status: {r.status_code}")
    print(f"    Total Logs Streamed: {len(r.json())}")
    assert r.status_code == 200

def test_scan_batch():
    print("\n[13] Testing POST /scan-batch (Batch APK Parallel Scanning)")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("AndroidManifest.xml", b"<manifest package='com.batch.test'></manifest>")
    apk_bytes = buf.getvalue()
    files = [
        ("files", ("app1.apk", apk_bytes, "application/vnd.android.package-archive")),
        ("files", ("app2.apk", apk_bytes, "application/vnd.android.package-archive"))
    ]
    r = httpx.post(f"{BASE_URL}/scan-batch", files=files)
    print(f"    Status: {r.status_code}")
    print(f"    Batch Response: {r.json().get('total_files')} file(s) processed.")
    assert r.status_code == 200

def main():
    print("=" * 65)
    print("      ScamShield End-to-End API Service Test Suite      ")
    print("=" * 65)
    
    results = {}
    tests = [
        ("GET /", test_root),
        ("GET /health", test_health),
        ("GET /stats", test_stats),
        ("POST /analyze", test_analyze_text),
        ("POST /analyze-voice", test_analyze_voice),
        ("POST /analyze-image", test_analyze_image),
        ("GET /dashboard", test_dashboard),
        ("GET /api/audit-logs", test_audit_logs),
        ("POST /scan-batch", test_scan_batch),
        ("GET /osint/hash/{hash}", test_osint_hash),
        ("POST /osint/urls", test_osint_urls),
        ("GET /osint/ip/{ip}", test_osint_ip),
        ("POST /scan (APK)", test_scan_apk),
    ]
    
    for name, test_func in tests:
        try:
            test_func()
            results[name] = "PASSED (HTTP 200 OK)"
        except Exception as e:
            results[name] = f"FAILED: {e}"
            
    print("\n" + "=" * 65)
    print("                  FINAL TEST REPORT MATRIX                 ")
    print("=" * 65)
    for endpoint, status in results.items():
        print(f"  • {endpoint:<28} : {status}")
    print("=" * 65)

if __name__ == "__main__":
    main()
