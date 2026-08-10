import io
import zipfile
import httpx

def main():
    # Create test APK in memory
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("AndroidManifest.xml", b"<manifest package='com.security.test'></manifest>")
        zf.writestr("classes.dex", b"https://bit.ly/suspicious-link-check AIzaSyDummyKeyForTesting1234567890")
    
    apk_bytes = buf.getvalue()
    
    url = "http://127.0.0.1:8000/scan"
    print(f"Sending test APK ({len(apk_bytes)} bytes) to {url}...")
    
    r = httpx.post(
        url,
        files={"file": ("test_security.apk", apk_bytes, "application/vnd.android.package-archive")},
        timeout=15.0
    )
    
    print(f"Response Status Code: {r.status_code}")
    if r.status_code == 200:
        data = r.json()
        print("ScamShield Server Response Summary:")
        print(f"  • Risk Level: {data['risk']['level']} ({data['risk']['score']}/100)")
        print(f"  • VirusTotal Service: {data['osint']['virustotal']}")
        print(f"  • Safe Browsing Service: {data['osint']['safe_browsing']}")
        print(f"  • Explanation: {data['ai_explanation']}")
        print("\nSUCCESS: The APK scanning pipeline and service endpoints are fully operational!")
    else:
        print(f"ERROR Response: {r.text}")

if __name__ == "__main__":
    main()
