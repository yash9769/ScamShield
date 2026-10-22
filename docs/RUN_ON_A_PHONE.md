# Running ScamShield on a real phone

VirusTotal, Google Safe Browsing, APK analysis (androguard + YARA), AI analysis,
voice and image scanning, scam trends and "was this right?" feedback all run on
the **ScamShield server**, not inside the app. Their API keys must never be put
in an APK, so the app asks the server to do those checks.

An APK on a real phone cannot find a server on its own. (Older builds hardcoded
`10.0.2.2`, which only exists inside the Android emulator.) Until the app has a
server address, those features report "unavailable" and scans fall back to the
on-device engine, which has no VirusTotal and no androguard.

## 1. Start the right server

The app needs the API in **`server/`**, not `backend/` (that is the separate v2
API, which has none of the endpoints the app calls).

```bash
cd server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env        # then edit server/.env, see below
uvicorn main:app --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` is what lets a phone reach it. Without it only the computer
itself can.

Put the keys in **`server/.env`** (not `backend/.env`):

```
VIRUSTOTAL_API_KEY=...
GOOGLE_SAFE_BROWSING_API_KEY=...
ABUSEIPDB_API_KEY=...
GROQ_API_KEY=...        # or GEMINI_API_KEY, for AI analysis
ADMIN_API_KEY=pick-a-long-random-string
```

Google Safe Browsing also needs the **Safe Browsing API enabled** for the key's
Google Cloud project (APIs & Services -> Library) and allowed in the key's API
restrictions. A key that is not enabled answers HTTP 403, and the server then
reports "lookup failed".

## 2. Tell the app where it is

1. Put the phone and the computer on the **same Wi-Fi**.
2. Find the computer's Wi-Fi address (`ipconfig` on Windows, `ifconfig` or
   `ip addr` on Linux and Mac), for example `192.168.1.5`.
3. In the app: **Profile -> Server address**, enter `http://192.168.1.5:8000`,
   tap **Test**.

The test shows whether the server answers and which integrations it has keys
for (VirusTotal, Safe Browsing, AbuseIPDB, androguard, YARA, AI). A line saying
"not set up on this server" means that provider's key is missing in
`server/.env`. If Windows Firewall asks, allow Python on private networks.

## 3. Or build the address into the APK

```bash
flutter build apk --release --dart-define=SCAMSHIELD_BACKEND_URL=http://192.168.1.5:8000
```

An address saved in the app overrides this one.

## What needs the server

| Feature | Without a server |
|---|---|
| VirusTotal, Google Safe Browsing, AbuseIPDB | "Not run" / unavailable |
| APK analysis (androguard, YARA) | On-device scan only |
| AI text analysis | On-device rules only |
| Voice and image scanning | Not possible (needs speech-to-text and OCR) |
| Scam trends, community reports, "was this right?" | Trends unavailable; feedback is saved on the phone and sent later |
| Accounts, family alerts, sync, leaderboard | Not possible |

Everything else works with no server: text scan rules, the QR breakdown, the
Cybercrime guide, history, Safe Vault and breach lookups.
