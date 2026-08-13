# Security Policy

ScamShield is a consumer scam-detection product. We take security
vulnerabilities seriously and treat user safety — especially the handling of
sensitive messages, contacts, and device data — as the top priority.

## Supported Versions

Only the latest release on the `main` branch is supported with security
updates. Older feature releases are not patched.

| Version | Supported          |
| ------- | ------------------ |
| latest (`main`) | :white_check_mark: |
| older releases | :x:                |

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for a security vulnerability.

Report it privately so we can fix it before details are public:

- **Preferred:** GitHub Security Advisory (the private report flow under the
  repository's *Security → Report a vulnerability* tab).
- **Fallback:** email a description to the maintainers with the subject
  `[SECURITY] <short summary>`. Include a plain-text description (no
  screenshots of secrets), affected versions, and any proof-of-concept
  (as a gist or archive, never raw credentials).

Please include:

1. The affected component (Flutter client, FastAPI backend, admin dashboard,
   APK analysis pipeline, OSINT proxy, ...).
2. Steps to reproduce, including any configuration needed.
3. Expected vs. actual behaviour, and the security impact you believe this has.

### What to expect

- **Acknowledgment:** within 3 business days, we confirm receipt and assign a
  tracking identifier.
- **Status update:** every 5 business days until a fix lands, we post a status
  update on the private report.
- **Resolution:** a fix is released as quickly as the severity warrants. On
  release, the report is closed and — unless the reporter prefers otherwise —
  acknowledged publicly (including in release notes where appropriate).

### Disclosure policy

- We coordinate disclosure. We ask that you **do not** publish details of a
  vulnerability before a fix is released (typically the release day).
- Once a fix is available, we encourage public disclosure and credit
  researchers who reported responsibly.
- Reports that turn out not to be vulnerabilities will be closed with an
  explanation.

## Security-relevant areas

The following are of particular interest and are reviewed on every change:

- **Admin endpoints** (`/dashboard`, `/api/audit-logs`) — keyed by
  `ADMIN_API_KEY`; must never run with a default/guessable key.
- **Client authentication** — per-device anonymous tokens and server API keys;
  credential fingerprints must never be stored or logged as raw values.
- **Privacy** — raw messages/emails/OTPs are never persisted or logged
  (audit logs store only SHA-256 fingerprints and lengths).
- **APK analysis pipeline** — untrusted input (APKs, images, audio) parsed
  in-process by Androguard/JADX/YARA; resource exhaustion and parser
  vulnerabilities are treated as high severity.
- **Credential handling** — API keys for Gemini, VirusTotal, MobSF, etc. are
  server-side environment variables only; they must never be embedded in the
  mobile client or committed to the repository.
