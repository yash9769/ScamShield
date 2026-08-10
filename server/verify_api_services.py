from __future__ import annotations
import asyncio
import hashlib
import io
import os
import zipfile
import httpx
from dotenv import load_dotenv

# Load server environment
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), ".env"))

GEMINI_API_KEY           = os.getenv("GEMINI_API_KEY", "").strip()
GROQ_API_KEY             = os.getenv("GROQ_API_KEY", "").strip()
VIRUSTOTAL_API_KEY       = os.getenv("VIRUSTOTAL_API_KEY", "").strip()
GOOGLE_SAFE_BROWSING_KEY = os.getenv("GOOGLE_SAFE_BROWSING_API_KEY", "").strip()
ABUSEIPDB_API_KEY        = os.getenv("ABUSEIPDB_API_KEY", "").strip()

# Resolve effective Groq key (also accept gsk_ keys placed in GEMINI_API_KEY)
_groq_key = GROQ_API_KEY or (GEMINI_API_KEY if GEMINI_API_KEY.startswith("gsk_") else "")

print("=" * 65)
print("     ScamShield API Services & Key Verification Diagnostics     ")
print("=" * 65)

async def test_gemini():
    print("\n[1] Testing Google Gemini AI Service...")
    if not GEMINI_API_KEY or GEMINI_API_KEY.startswith("gsk_"):
        print("    └─ GEMINI_API_KEY is NOT set (or is a Groq key) — skipping Gemini test.")
        return False
    try:
        from google import genai
        client = genai.Client(api_key=GEMINI_API_KEY)
        response = client.models.generate_content(
            model="gemini-2.0-flash",
            contents="Say 'Gemini OK'",
        )
        print(f"    └─ Gemini API Response SUCCESS: '{response.text.strip()}'")
        return True
    except Exception as e:
        print(f"    └─ Gemini API Test FAILED: {e}")
        return False

async def test_groq():
    print("\n[1b] Testing Groq AI Service...")
    if not _groq_key:
        print("    └─ GROQ_API_KEY is NOT set in server/.env — skipping.")
        return False
    try:
        async with httpx.AsyncClient(timeout=15.0) as c:
            r = await c.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={"Authorization": f"Bearer {_groq_key}", "Content-Type": "application/json"},
                json={
                    "model": "llama-3.3-70b-versatile",
                    "messages": [{"role": "user", "content": "Say 'Groq OK'"}],
                    "max_tokens": 10,
                },
            )
        r.raise_for_status()
        reply = r.json()["choices"][0]["message"]["content"].strip()
        print(f"    └─ Groq API SUCCESS: '{reply}'")
        return True
    except Exception as e:
        print(f"    └─ Groq API Test FAILED: {e}")
        return False

async def test_virustotal():
    print("\n[2] Testing VirusTotal API v3 Service...")
    if not VIRUSTOTAL_API_KEY:
        print("    └─ VIRUSTOTAL_API_KEY is NOT set in server/.env (Unverified mode active).")
        return False
    test_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" # Empty file SHA-256
    try:
        async with httpx.AsyncClient(timeout=10.0) as c:
            r = await c.get(
                f"https://www.virustotal.com/api/v3/files/{test_hash}",
                headers={"x-apikey": VIRUSTOTAL_API_KEY},
            )
        if r.status_code in (200, 404):
            print(f"    └─ VirusTotal API SUCCESS (HTTP {r.status_code}): Key is valid and authenticated!")
            return True
        else:
            print(f"    └─ VirusTotal API FAILED (HTTP {r.status_code}): {r.text[:100]}")
            return False
    except Exception as e:
        print(f"    └─ VirusTotal API Error: {e}")
        return False

async def test_safe_browsing():
    print("\n[3] Testing Google Safe Browsing API v4 Service...")
    if not GOOGLE_SAFE_BROWSING_KEY:
        print("    └─ GOOGLE_SAFE_BROWSING_API_KEY is NOT set in server/.env.")
        return False
    try:
        payload = {
            "client": {"clientId": "scamshield-test", "clientVersion": "3.0"},
            "threatInfo": {
                "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING"],
                "platformTypes": ["ANY_PLATFORM"],
                "threatEntryTypes": ["URL"],
                "threatEntries": [{"url": "http://testsafebrowsing.appspot.com/s/phishing.html"}],
            },
        }
        async with httpx.AsyncClient(timeout=10.0) as c:
            r = await c.post(
                f"https://safebrowsing.googleapis.com/v4/threatMatches:find?key={GOOGLE_SAFE_BROWSING_KEY}",
                json=payload,
            )
        if r.status_code == 200:
            print(f"    └─ Google Safe Browsing API SUCCESS (HTTP 200): Key is valid!")
            return True
        else:
            print(f"    └─ Google Safe Browsing FAILED (HTTP {r.status_code}): {r.text[:100]}")
            return False
    except Exception as e:
        print(f"    └─ Google Safe Browsing Error: {e}")
        return False

async def test_abuseipdb():
    print("\n[4] Testing AbuseIPDB Service...")
    if not ABUSEIPDB_API_KEY:
        print("    └─ ABUSEIPDB_API_KEY is NOT set in server/.env.")
        return False
    try:
        async with httpx.AsyncClient(timeout=10.0) as c:
            r = await c.get("https://api.abuseipdb.com/api/v2/check",
                            params={"ipAddress": "8.8.8.8", "maxAgeInDays": 90},
                            headers={"Accept": "application/json", "Key": ABUSEIPDB_API_KEY})
        if r.status_code == 200:
            print(f"    └─ AbuseIPDB API SUCCESS (HTTP 200): Key is valid!")
            return True
        else:
            print(f"    └─ AbuseIPDB API FAILED (HTTP {r.status_code}): {r.text[:100]}")
            return False
    except Exception as e:
        print(f"    └─ AbuseIPDB Error: {e}")
        return False

async def test_apk_scan_pipeline():
    print("\n[5] Executing Mock APK Scan Pipeline Test...")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("AndroidManifest.xml", b"<manifest package='com.test.app'></manifest>")
        zf.writestr("classes.dex", b"https://bit.ly/suspicious-test-link AIzaSyDummyGoogleKey1234567890123")
    apk_data = buf.getvalue()
    
    # Import analyze_apk_file from server.main
    from main import analyze_apk_file
    import tempfile
    
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".apk")
    tmp.write(apk_data)
    tmp.close()
    
    try:
        report = await analyze_apk_file(tmp.name, len(apk_data))
        print("    └─ APK Scan Pipeline Executed Successfully!")
        print(f"       • Risk Score: {report['risk']['score']}/100 ({report['risk']['level']})")
        print(f"       • VirusTotal Status: {report['osint']['virustotal'].get('note')}")
        print(f"       • Safe Browsing Status: {report['osint']['safe_browsing']['results'][0].get('note') if report['osint']['safe_browsing']['results'] else 'None'}")
        print(f"       • Secrets Found: {list(report['secrets']['findings'].keys())}")
        return True
    except Exception as e:
        print(f"    └─ APK Scan Pipeline Exception: {e}")
        return False
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass

async def main():
    await test_gemini()
    await test_groq()
    await test_virustotal()
    await test_safe_browsing()
    await test_abuseipdb()
    await test_apk_scan_pipeline()
    print("\n" + "=" * 65)

if __name__ == "__main__":
    asyncio.run(main())
