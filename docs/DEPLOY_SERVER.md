# Put the server online so the APK works for everyone

A server on your PC is only reachable on your own Wi-Fi. To have VirusTotal, Safe Browsing,
androguard, trends, feedback and the rest work on any phone, run `server/` on a public host.

## 1. Deploy on Render (free tier)

1. Rotate your API keys first (the old ones were exposed). Use only the new ones below.
2. render.com -> New -> Blueprint -> pick this GitHub repo. It reads `render.yaml`.
3. In the service's Environment tab, paste your keys:
   `VIRUSTOTAL_API_KEY`, `GOOGLE_SAFE_BROWSING_API_KEY`, `ABUSEIPDB_API_KEY`, `GEMINI_API_KEY` / `GROQ_API_KEY`.
4. Wait for the deploy, then open `https://<name>.onrender.com/selftest` in a browser.
   Each integration shows `ok: true/false` and why. Fix any `false` before building the APK.

Free tier notes: the service sleeps after ~15 min idle, so the first request takes 30-60 s.
Accounts/audit use local SQLite and reset on redeploy. Voice (Whisper) and image (EasyOCR)
are not in `requirements.txt` and will say "unavailable" unless you add them (needs more RAM).

Google Safe Browsing: enable "Safe Browsing API" in the Google Cloud project that owns the key,
and allow it under the key's API restrictions.

## 2. Build the APK pointing at it

    flutter build apk --release --dart-define=SCAMSHIELD_BACKEND_URL=https://<name>.onrender.com

Install it. Profile -> Server address -> Test should show every service with a tick.
Users can still override the address there.

## Quick local alternative (demo only)

    cd server && uvicorn main:app --host 0.0.0.0 --port 8000
    cloudflared tunnel --url http://localhost:8000     # prints a public https URL
