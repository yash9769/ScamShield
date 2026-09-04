# ScamShield — Third-Party Data Processors

**Date:** 2026-09-04
**Scope:** every external service that can receive user-submitted data from the live system (`server/main.py` + `lib/`). The dormant `backend/app/` tree (MobSF, Whisper, EasyOCR, WHOIS, additional Gemini/Groq call sites) is documented separately at the bottom — it processes nothing today because nothing starts it (see `DPDP_AUDIT.md` §0).

Columns marked `VERIFY` could not be confirmed from the repository or public provider documentation alone and require the operator to confirm directly with the vendor (e.g., current DPA terms, server region, retention policy) before this table can be relied on for a compliance filing.

## Live system (`server/`, the backend the app actually calls)

| Provider | Data Sent | Purpose | Storage / Retention (at provider) | Country / Region | Required? |
|---|---|---|---|---|---|
| **Groq** (LLM inference, `llama-3.3-70b`/etc.) | Full text of the user's submitted message (`/analyze`), or a derived text summary of voice/image input | AI-powered scam classification | `VERIFY` — governed by Groq's API terms; not configurable from this codebase | `VERIFY` — Groq's stated infrastructure regions | No — only called if `GROQ_API_KEY` is set; heuristic engine is a full fallback (`server/main.py:308-346,887`) |
| **Google Gemini** (`google-genai` SDK) | Same as Groq — used only if Groq is unavailable/unconfigured | AI-powered scam classification (fallback provider) | `VERIFY` — governed by Google's Gemini API terms | `VERIFY` | No — key-gated, same fallback logic (`server/main.py:349-378`) |
| **VirusTotal** | SHA-256 hash of an uploaded APK, or a hash the user queries directly via `/osint/hash/{hash}` | File-reputation lookup | `VERIFY` — VirusTotal's terms note that submitted **hashes** (not the file itself, in this integration) may be retained/shared across its multi-engine partner network | `VERIFY` | No — key-gated (`server/main.py:535-554`); degrades to "not configured" |
| **Google Safe Browsing** | URLs extracted from a scanned APK's strings, or URLs the user submits via `/osint/urls` | URL-reputation lookup | `VERIFY` — governed by Google's Safe Browsing API terms | `VERIFY` | No — key-gated (`server/main.py:556-582`) |
| **AbuseIPDB** | An IP address the user queries via `/osint/ip/{ip}` | IP-reputation lookup | `VERIFY` — governed by AbuseIPDB's terms | `VERIFY` | No — key-gated, only reachable via this one route (`server/main.py:584-599`) |
| **XposedOrNot** | The email address the user enters into the breach-lookup feature, sent in a URL query string (`.../breach-analytics?email=...`) | Credential/data-breach exposure lookup | `VERIFY` — XposedOrNot's stated retention/logging policy; ScamShield's own server does **not** persist the email (confirmed — no DB write in `check_email_breach`, `server/main.py:1090-1175`) | `VERIFY` | Yes, for this feature's core purpose — always called when the route is hit; no ScamShield-side key required (public endpoint) |
| **crt.sh** (Sectigo Certificate Transparency log search) | A domain name extracted from a scanned message/APK's URLs | Domain-trust signal: certificate issuance history/age | `VERIFY` — crt.sh's own retention policy (it mirrors public CT logs, which are themselves permanent public records by design) | `VERIFY` | No — always attempted (keyless, `server/main.py` `crtsh_domain_check`), but its result only ever adds a bounded risk-score nudge, never a hard verdict |
| **RDAP** (via `rdap.org`, which routes to the authoritative registry's own RDAP server, e.g. Verisign for `.com`) | A domain name extracted from a scanned message/APK's URLs | Domain-trust signal: registration age | `VERIFY` — the destination RDAP server depends on the domain's TLD/registry; each has its own policy. RDAP responses are the modern, structured successor to public WHOIS data and are themselves public registry records | `VERIFY` | No — same as crt.sh above (`server/main.py` `rdap_domain_age`) |

### Removed: URLhaus (abuse.ch) — was broken, now removed rather than fixed with a bypass

Client code (`lib/services/osint_service.dart`) previously called `https://urlhaus-api.abuse.ch/v1/url/` directly from the device with no key, on the understanding that this specific legacy endpoint was keyless. As of 2026-09-04 that endpoint now returns an anti-bot "verify-ua" redirect for any non-browser request — abuse.ch has since put URLhaus behind bot verification, and its replacement Community API requires a registered `Auth-Key`. ScamShield does not attempt to bypass bot/CAPTCHA verification. The dead call has been **removed**, not patched around; the same purpose (screening a URL's domain for scam-infrastructure signals when Google Safe Browsing is unavailable) is now served by the crt.sh/RDAP domain-intelligence check above. If URLhaus's own Auth-Key becomes available and the operator wants to re-add it, it must be a **server-side** key (never embedded in the client, per the existing pattern for every other keyed provider here).

### Data NOT currently sent to any third party (despite UI/feature descriptions suggesting otherwise)

- **Screenshot images** — not uploaded anywhere; the client only analyzes the filename string locally (`lib/services/file_scanner_service.dart:154-166`). `/analyze-image` exists server-side and would forward extracted OCR text to Groq/Gemini if reached, but no client screen calls it.
- **Voice/audio recordings** — not uploaded anywhere; no screen in `lib/` calls the voice-upload path. `/analyze-voice` exists server-side, parses only WAV container metadata (not real transcription — no Whisper integration in `server/`), and forwards a short derived text summary to Groq/Gemini if reached.
- **Safe Vault contents** — never leaves the device (`lib/screens/safe_vault_screen.dart`).
- **HaveIBeenPwned** — code exists in `lib/services/breach_service.dart:180,314-337` to call HIBP directly with an API key, but the key is never set anywhere in the app, so this path is dead in the shipped client; the feature users actually reach goes through the ScamShield server to XposedOrNot instead.

## Dormant system (`backend/app/` — not started by anything, documented for completeness)

If this tree were ever deployed, it would additionally send data to:

| Provider | Data Sent | Purpose | Required? |
|---|---|---|---|
| **MobSF** (self-hosted, `docker-compose.yml`) | The complete APK binary | Deep dynamic/static malware analysis | Would be always-called for `/scan` in this tree's design |
| **OpenAI Whisper** (local, no network egress) | N/A — runs on the server's own hardware, not a third-party network call | Voice-note transcription | Optional dependency |
| **EasyOCR** (local, no network egress) | N/A — same as above | Screenshot text extraction | Optional dependency |
| **WHOIS lookups** | Domains extracted from message content | Domain-registration reputation | `backend/app/services/osint_service.dart` equivalent — `VERIFY` which registrar/WHOIS provider is used |
| Groq / Gemini | Same pattern as the live system, plus AI-generated human-readable explanations of APK risk (`ai_explanation.py`) | AI classification + explanation | Key-gated |
| VirusTotal / Google Safe Browsing / AbuseIPDB | Same pattern as the live system | Reputation lookups | Key-gated |
| XposedOrNot | Raw email in a URL query string (`services/xposedornot.py:35`) | Breach lookup | Same as live system |

**Not implemented/reached by either tree today:** no analytics SDK, no crash-reporting SDK, no advertising SDK (confirmed via dependency and code review — `DPDP_AUDIT.md` §1 item 12).

## Data minimisation already in place

- User identifiers, device identifiers, and account information are **never** sent to any third party listed above — only the specific content needed for the specific lookup (message text, a file hash, a URL, an IP, or an email the user chose to submit) crosses the boundary.
- `POST /scan`'s certificate-parsing response can surface a third party's own data (the **APK signer's** name/organization from the certificate) back to the requester — this is data about the app developer, not the ScamShield user, and is not sent onward to any of the providers above.

## Action items

1. `VERIFY` cells above require direct confirmation from each vendor (current DPA, data region, retention) before this document can support a compliance filing — `REQUIRES PRODUCT/LEGAL DECISION`.
2. Decide whether `backend/app/` will ever be resurrected; if so, its third-party footprint (materially larger — adds MobSF, WHOIS) must be re-reviewed and this table updated before deployment.
3. If `/analyze-voice` or `/analyze-image` are completed as real features, this document must be updated *before* release, since it would newly send audio/image-derived content to Groq/Gemini.
4. crt.sh and RDAP were added 2026-09-04 as free, keyless replacements for the broken URLhaus integration. Only a domain name (never message content, never a user identifier) is sent to either. Both are read-only lookups against public registry/CT-log data — no user data is submitted *to* the domain being looked up.
