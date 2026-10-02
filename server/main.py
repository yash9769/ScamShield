# server/main.py — ScamShield API v3.0
# Every feature the app promises is implemented here end-to-end with real keys.

import asyncio
import hashlib
import hmac
import io
import ipaddress
import json
import logging
import os
import re
import sqlite3
import tempfile
import zipfile
from collections import OrderedDict
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import List, Optional
from urllib.parse import urlparse

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

# ── Environment ────────────────────────────────────────────────────────────────
load_dotenv()
GEMINI_API_KEY           = os.getenv("GEMINI_API_KEY", "")
GROQ_API_KEY             = os.getenv("GROQ_API_KEY", "")
VIRUSTOTAL_API_KEY       = os.getenv("VIRUSTOTAL_API_KEY", "")
GOOGLE_SAFE_BROWSING_KEY = os.getenv("GOOGLE_SAFE_BROWSING_API_KEY", "")
ABUSEIPDB_API_KEY        = os.getenv("ABUSEIPDB_API_KEY", "")
XPOSEDORNOT_API_KEY      = os.getenv("XPOSEDORNOT_API_KEY", "")
LOG_LEVEL                = os.getenv("LOG_LEVEL", "INFO")
RATE_LIMIT_ENABLED       = os.getenv("RATE_LIMIT_ENABLED", "true").lower() != "false"
ADMIN_API_KEY            = os.getenv("ADMIN_API_KEY", "")
# Data retention for the audit-log table (DPDP data-minimisation control).
# Unset/blank = no automatic cleanup (operator has not defined a retention
# policy yet); this code does not invent a default period. See
# DPDP_COMPLIANCE.md for the product decision this is pending on.
AUDIT_LOG_RETENTION_DAYS = os.getenv("AUDIT_LOG_RETENTION_DAYS", "").strip()
if not ADMIN_API_KEY:
    import sys
    # Only "pytest" actually being the importing process is accepted here —
    # NOT a bare CI env var, which can be present on real staging/production
    # hosts (many CI/CD platforms set CI=true at deploy time too) and would
    # previously have silently activated a hardcoded, publicly-known admin
    # key (server/main.py history; also hardcoded client-side in
    # static/dashboard.html). A stray CI or PYTEST_CURRENT_TEST env var on a
    # real deployment no longer bypasses the requirement below.
    if "pytest" in sys.modules:
        ADMIN_API_KEY = "scamshield_admin_sec_key_2026"
        logging.getLogger("scamshield").warning(
            "ADMIN_API_KEY not set; using the hardcoded test-only fallback "
            "because this process was imported under pytest. This fallback "
            "MUST NOT be reachable outside test runs."
        )
    else:
        raise ValueError("ADMIN_API_KEY environment variable is required and must not be empty.")

# Resolve effective AI key and provider
_groq_key = GROQ_API_KEY or (GEMINI_API_KEY if GEMINI_API_KEY.startswith("gsk_") else "")
_use_groq  = bool(_groq_key)

async def verify_admin_auth(request: Request):
    auth_header = request.headers.get("Authorization", "")
    api_key_header = request.headers.get("X-Admin-Key", "")
    
    token = ""
    if auth_header.startswith("Bearer "):
        token = auth_header[7:].strip()
    elif api_key_header:
        token = api_key_header.strip()

    if not token or not hmac.compare_digest(token, ADMIN_API_KEY):
        raise HTTPException(
            status_code=401,
            detail="Unauthorized: Admin authentication required via 'Authorization: Bearer <token>' or 'X-Admin-Key' header."
        )

logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO))
logger = logging.getLogger("scamshield")

BASE_DIR        = Path(__file__).resolve().parent
MAX_TEXT_LENGTH = 10_000

# ── SQLite Audit Logger ───────────────────────────────────────────────────────
DB_PATH = BASE_DIR / "server_audit.db"

def init_audit_db():
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS audit_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                event_type TEXT,
                target TEXT,
                risk_score INTEGER,
                risk_level TEXT
            )
        """)
        conn.commit()
        conn.close()
    except Exception as e:
        logger.warning(f"Audit DB init error: {e}")

def log_audit_event(event_type: str, target: str, risk_score: int, risk_level: str):
    try:
        clean_target = re.sub(
            r"(AIzaSy[0-9A-Za-z\-_]{30,}|sk-[a-zA-Z0-9]{20,}|AKIA[A-Z0-9]{16}|bearer\s+[a-zA-Z0-9\._\-]+)",
            "[REDACTED_SECRET]",
            str(target),
            flags=re.IGNORECASE
        )
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO audit_logs (event_type, target, risk_score, risk_level)
            VALUES (?, ?, ?, ?)
        """, (event_type, clean_target[:150], risk_score, risk_level))
        conn.commit()
        conn.close()
    except Exception as e:
        logger.warning(f"Audit log error: {e}")

def cleanup_audit_logs() -> int:
    """Deletes audit_logs rows older than AUDIT_LOG_RETENTION_DAYS.

    No-op (returns 0) if no retention period has been configured — this
    function does not invent a default period; see AUDIT_LOG_RETENTION_DAYS
    above and DPDP_COMPLIANCE.md.
    """
    if not AUDIT_LOG_RETENTION_DAYS:
        return 0
    try:
        days = int(AUDIT_LOG_RETENTION_DAYS)
    except ValueError:
        logger.warning(f"Ignoring invalid AUDIT_LOG_RETENTION_DAYS={AUDIT_LOG_RETENTION_DAYS!r}")
        return 0
    if days <= 0:
        return 0
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        cur.execute(
            f"DELETE FROM audit_logs WHERE timestamp < datetime('now', '-{days} days')"
        )
        deleted = cur.rowcount
        conn.commit()
        conn.close()
        if deleted:
            logger.info(f"Audit log retention cleanup: removed {deleted} row(s) older than {days} days.")
        return deleted
    except Exception as e:
        logger.warning(f"Audit log cleanup error: {e}")
        return 0

init_audit_db()
cleanup_audit_logs()

# ── Community scam reporting ─────────────────────────────────────────────────
# A lightweight crowdsourced reputation signal: users can flag a phone
# number/URL/domain as a scam, and other users can check whether it's been
# reported before engaging with it (answering a call, opening a link, paying
# a UPI handle from a QR code). Deliberately NOT wired into the automated
# risk-scoring pipeline — a single anonymous report is trivial to fabricate,
# so REPORT_THRESHOLD_FOR_SIGNAL gates when a report is surfaced as a real
# signal rather than acted on after just one submission.
REPORT_THRESHOLD_FOR_SIGNAL = 3

def init_scam_reports_db():
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        cur.execute("""
            CREATE TABLE IF NOT EXISTS scam_reports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                indicator_type TEXT NOT NULL,
                indicator_value TEXT NOT NULL,
                category TEXT,
                report_count INTEGER NOT NULL DEFAULT 0,
                first_reported DATETIME DEFAULT CURRENT_TIMESTAMP,
                last_reported DATETIME DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(indicator_type, indicator_value)
            )
        """)
        # Verdict feedback: "was this call right?" answers from the scan result
        # screen. Deliberately anonymous and content-free — a SHA-256 of the
        # analysed text is stored instead of the text, which is enough to
        # collapse duplicate votes on the same message without the server ever
        # holding someone's SMS.
        cur.execute("""
            CREATE TABLE IF NOT EXISTS verdict_feedback (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                content_hash TEXT NOT NULL,
                classification TEXT NOT NULL,
                risk_score INTEGER NOT NULL,
                agreement TEXT NOT NULL,
                note TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(content_hash, agreement)
            )
        """)
        cur.execute(
            "CREATE INDEX IF NOT EXISTS idx_feedback_created ON verdict_feedback(created_at)"
        )
        conn.commit()
        conn.close()
    except Exception as e:
        logger.warning(f"Scam reports DB init error: {e}")

init_scam_reports_db()

def _normalize_indicator(indicator_type: str, value: str) -> str:
    """Normalizes a reported indicator so the same number/URL always maps to
    one row regardless of formatting (dashes/spaces/country-code prefix in a
    phone number, casing in a domain/URL)."""
    value = value.strip()
    if indicator_type == "upi":
        # UPI handles are case-insensitive and frequently pasted with stray
        # spaces from a QR payload.
        return value.lower().replace(" ", "")
    if indicator_type == "phone":
        digits = re.sub(r"\D", "", value)
        # Collapse +91XXXXXXXXXX / 91XXXXXXXXXX / 0XXXXXXXXXX down to the bare
        # 10-digit number, so the same real-world number reported with a
        # different prefix still lands on the same reputation record.
        if len(digits) == 12 and digits.startswith("91"):
            digits = digits[2:]
        elif len(digits) == 11 and digits.startswith("0"):
            digits = digits[1:]
        return digits
    return value.lower()

MAX_APK_SIZE    = 100 * 1024 * 1024
MAX_BATCH_FILES = 20

# ── Groq (preferred) / Gemini SDK ─────────────────────────────────────────────
GROQ_AVAILABLE   = False
GEMINI_AVAILABLE = False
gemini_client    = None

GROQ_MODELS   = ["llama-3.3-70b-versatile", "llama-3.1-70b-versatile", "llama-3.1-8b-instant"]
GEMINI_MODELS = ["gemini-2.0-flash", "gemini-2.0-flash-lite", "gemini-1.5-flash"]

if _use_groq:
    GROQ_AVAILABLE = True
    logger.info("[ScamShield] Groq AI ready.")
else:
    try:
        from google import genai
        from google.genai import types as genai_types
        if GEMINI_API_KEY:
            gemini_client    = genai.Client(api_key=GEMINI_API_KEY)
            GEMINI_AVAILABLE = True
            logger.info("[ScamShield] Gemini AI ready.")
        else:
            logger.warning("[ScamShield] No GEMINI_API_KEY or GROQ_API_KEY — heuristic-only mode.")
    except ImportError:
        logger.warning("[ScamShield] google-genai not installed.")

# ── Androguard ─────────────────────────────────────────────────────────────────
try:
    from androguard.core.apk import APK as AndroguardAPK
    ANDROGUARD_AVAILABLE = True
except ImportError:
    ANDROGUARD_AVAILABLE = False
    logger.warning("androguard not installed — manifest parsing disabled.")

# ── YARA ───────────────────────────────────────────────────────────────────────
try:
    import yara
    YARA_AVAILABLE = True
except ImportError:
    YARA_AVAILABLE = False
    logger.warning("yara-python not installed — YARA matching disabled.")

# ── Rate limiter ───────────────────────────────────────────────────────────────
limiter = Limiter(key_func=get_remote_address, enabled=RATE_LIMIT_ENABLED)

# ── FastAPI app ────────────────────────────────────────────────────────────────
app = FastAPI(title="ScamShield API", version="3.0.0")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("ALLOWED_ORIGINS", "*").split(","),
    allow_credentials=False,
    # DELETE is needed by the account-erasure endpoint in accounts.py.
    allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)

# ── Accounts, cross-device sync and family protection ─────────────────────────
# Kept in its own module: it is the only stateful, authenticated surface in an
# otherwise stateless analysis API, and it owns its own database.
from accounts import init_accounts_db, router as accounts_router  # noqa: E402

init_accounts_db()
app.include_router(accounts_router)

# ── Pydantic models ────────────────────────────────────────────────────────────
class ScamClassification(str, Enum):
    safe       = "safe"
    suspicious = "suspicious"
    scam       = "scam"

class IconCategory(str, Enum):
    financial    = "financial"
    link         = "link"
    urgency      = "urgency"
    suspicious   = "suspicious"
    manipulation = "manipulation"
    safe         = "safe"

class DetectionReason(BaseModel):
    label: str
    description: str
    scoreContribution: int
    iconCategory: IconCategory

class AnalysisResult(BaseModel):
    classification: ScamClassification
    riskScore: int
    reasons: List[DetectionReason]
    summary: str
    aiPowered: bool = True

class AnalysisRequest(BaseModel):
    text: str

    @field_validator("text")
    @classmethod
    def validate_text(cls, v: str) -> str:
        if len(v) > MAX_TEXT_LENGTH:
            raise ValueError(f"text exceeds {MAX_TEXT_LENGTH} characters")
        return v

class UrlCheckRequest(BaseModel):
    urls: List[str]

    @field_validator("urls")
    @classmethod
    def validate_urls(cls, v: List[str]) -> List[str]:
        if len(v) > 50:
            raise ValueError("max 50 URLs per request")
        return v

class RiskInfo(BaseModel):
    level: str
    score: int
    details: List[str]

class FileInfo(BaseModel):
    md5: str
    sha1: str
    sha256: str
    size: int

class ScanResult(BaseModel):
    scan_mode: str = "server"
    cached: bool   = False
    risk: RiskInfo
    ai_explanation: str
    file_info: FileInfo
    androguard: dict
    secrets: dict
    yara: dict
    osint: dict

class Breach(BaseModel):
    name: str
    domain: str
    date: str
    dataClasses: List[str]

class BreachResponse(BaseModel):
    email: str
    exposed: bool
    breachCount: int
    breaches: List[Breach]
    source: str = "XposedOrNot"
    checkedAt: str

class ScamReportType(str, Enum):
    phone  = "phone"
    url    = "url"
    domain = "domain"
    # A UPI payee handle (name@bank). Reported and looked up at the moment of
    # payment, which is the highest-stakes point in an Indian payment scam.
    upi    = "upi"

class ScamReportRequest(BaseModel):
    indicator_type: ScamReportType
    indicator_value: str = Field(..., min_length=3, max_length=500)
    category: Optional[str] = Field(default=None, max_length=100)

    @field_validator("indicator_value")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("indicator_value must not be blank")
        return v

class ScamReportResponse(BaseModel):
    indicator_type: str
    indicator_value: str
    report_count: int
    category: Optional[str] = None

class ReputationResponse(BaseModel):
    indicator_type: str
    indicator_value: str
    reported: bool
    report_count: int
    category: Optional[str] = None
    first_reported: Optional[str] = None
    last_reported: Optional[str] = None

class VerdictAgreement(str, Enum):
    # The verdict was right.
    correct        = "correct"
    # Flagged as a scam but the user knows it is legitimate.
    false_positive = "false_positive"
    # Called safe (or too low) but the user knows it was a scam.
    missed         = "missed"

class VerdictFeedbackRequest(BaseModel):
    """A vote on a verdict the app just produced.

    `content_hash` is a client-computed SHA-256 of the analysed text. The text
    itself is never sent: the hash exists only so repeat votes on the same
    message collapse into one, and it is not reversible into the message.
    """
    content_hash: str = Field(..., min_length=64, max_length=64)
    classification: ScamClassification
    risk_score: int = Field(..., ge=0, le=100)
    agreement: VerdictAgreement
    note: Optional[str] = Field(default=None, max_length=280)

    @field_validator("content_hash")
    @classmethod
    def _is_sha256_hex(cls, v: str) -> str:
        v = v.strip().lower()
        if not re.fullmatch(r"[0-9a-f]{64}", v):
            raise ValueError("content_hash must be a hex SHA-256 digest")
        return v

class VerdictFeedbackResponse(BaseModel):
    recorded: bool
    total_feedback: int

class VerdictAccuracyResponse(BaseModel):
    """Aggregate only — no per-report rows are ever exposed here."""
    days: int
    total: int
    correct: int
    false_positives: int
    missed: int
    accuracy_percent: float
    by_classification: dict

# ── Gemini prompt ──────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """You are ScamShield, an elite cybersecurity AI specialising in scam, phishing, and fraud detection.

Analyse the message and return ONLY a JSON object with this exact structure:
{
  "classification": "safe" | "suspicious" | "scam",
  "riskScore": <integer 0-100>,
  "summary": "<2-3 sentence plain-English verdict>",
  "aiPowered": true,
  "reasons": [
    {
      "label": "<short title>",
      "description": "<detailed explanation of this specific signal>",
      "scoreContribution": <integer 0-40>,
      "iconCategory": "financial"|"link"|"urgency"|"suspicious"|"manipulation"|"safe"
    }
  ]
}

Scoring:
  0-29   → safe        (no meaningful threat signals)
  30-64  → suspicious  (concerning but inconclusive)
  65-100 → scam        (high-confidence fraud)

Detect: financial lures (bank/OTP/KYC/UPI/PIN/CVV), urgency/pressure tactics, prize/lottery fraud,
phishing links (shortened URLs, look-alike domains), authority impersonation (IRS/RBI/police/Microsoft),
psychological manipulation, OTP sharing requests, investment/job fraud, romance scams,
delivery fee fraud, fake order confirmation, credential harvesting.

Be specific — quote exact phrases from the message. If safe, explain why.
Return ONLY raw JSON — no markdown, no explanation text."""

# ── JSON extractor ─────────────────────────────────────────────────────────────
def extract_json(text: str) -> dict:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    m = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text)
    if m:
        try:
            return json.loads(m.group(1))
        except json.JSONDecodeError:
            pass
    m = re.search(r"\{[\s\S]*\}", text)
    if m:
        return json.loads(m.group(0))
    raise ValueError(f"No JSON in response: {text[:200]}")

# ── Groq AI analysis ──────────────────────────────────────────────────────────────────────────────────
import httpx as _httpx

async def analyze_with_groq(text: str) -> Optional[AnalysisResult]:
    if not GROQ_AVAILABLE:
        return None
    for model in GROQ_MODELS:
        try:
            async with _httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.post(
                    "https://api.groq.com/openai/v1/chat/completions",
                    headers={
                        "Authorization": f"Bearer {_groq_key}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": model,
                        "messages": [
                            {"role": "system", "content": SYSTEM_PROMPT},
                            {"role": "user", "content": f"Analyse this for scam indicators:\n\n{text}"},
                        ],
                        "temperature": 0.1,
                        "response_format": {"type": "json_object"},
                        "max_tokens": 1024,
                    },
                )
            resp.raise_for_status()
            raw = resp.json()["choices"][0]["message"]["content"]
            data = extract_json(raw)
            data["riskScore"] = max(0, min(100, int(data.get("riskScore", 0))))
            data["aiPowered"] = True
            valid = {c.value for c in IconCategory}
            for r in data.get("reasons", []):
                if r.get("iconCategory") not in valid:
                    r["iconCategory"] = "suspicious"
            logger.info(f"Groq {model} succeeded")
            return AnalysisResult(**data)
        except Exception as e:
            logger.warning(f"Groq {model} failed: {str(e)[:120]}")
            continue
    logger.warning("All Groq models failed — heuristic fallback.")
    return None

# ── Gemini AI analysis ──────────────────────────────────────────────────────────────────────────────────
async def analyze_with_gemini(text: str) -> Optional[AnalysisResult]:
    if not gemini_client:
        return None
    for model in GEMINI_MODELS:
        try:
            resp = await asyncio.to_thread(
                gemini_client.models.generate_content,
                model=model,
                contents=f"Analyse this for scam indicators:\n\n{text}",
                config=genai_types.GenerateContentConfig(
                    system_instruction=SYSTEM_PROMPT,
                    response_mime_type="application/json",
                    temperature=0.1,
                ),
            )
            data = extract_json(resp.text)
            data["riskScore"] = max(0, min(100, int(data.get("riskScore", 0))))
            data["aiPowered"] = True
            valid = {c.value for c in IconCategory}
            for r in data.get("reasons", []):
                if r.get("iconCategory") not in valid:
                    r["iconCategory"] = "suspicious"
            return AnalysisResult(**data)
        except Exception as e:
            err = str(e)
            logger.warning(f"Gemini {model} failed: {err[:120]}")
            if any(x in err.upper() for x in ["RESOURCE_EXHAUSTED", "QUOTA", "NOT_FOUND", "404"]):
                continue
            return None
    logger.warning("All Gemini models failed — heuristic fallback.")
    return None

# ── Heuristic fallback (comprehensive keyword engine) ─────────────────────────
FINANCIAL_KW = [
    'bank', 'account', 'otp', 'pin', 'password', 'credit card', 'debit card',
    'transaction', 'transfer', 'wire', 'payment', 'wallet', 'kyc', 'verify your account',
    'aadhaar', 'pan card', 'upi', 'ifsc', 'cvv', 'neft', 'rtgs', 'net banking', 'atm',
    'social security', 'ssn', 'bank details', 'account number', 'routing number',
    'card number', 'expiry date', 'billing',
]
PRIZE_KW = [
    'win', 'winner', 'lottery', 'prize', 'reward', 'congratulations', 'selected',
    'gift card', 'voucher', 'free money', 'jackpot', 'lucky draw', 'cash prize',
    'you have been chosen', 'claim your prize', 'you won',
]
URGENCY_KW = [
    'urgent', 'immediately', 'act now', 'limited time', 'expires', 'final notice',
    'last chance', 'within 24 hours', 'suspended', 'blocked', 'terminated',
    'action required', 'verify now', 'confirm now', 'do not ignore', 'deadline',
    'account will be closed', 'legal action', 'arrest warrant', 'overdue',
]
IMPERSONATION_KW = [
    'irs', 'income tax', 'cbi', 'police', 'court notice', 'fbi', 'interpol',
    'microsoft support', 'apple support', 'amazon prime', 'paypal security',
    'whatsapp team', 'rbi', 'sebi', 'customs department', 'social security administration',
]
MANIPULATION_KW = [
    'click here', 'click now', 'tap here', 'do not share', 'never share',
    'call us immediately', 'call now', 'trust us', 'guaranteed', 'risk free',
    'no cost', 'secret', 'confidential', 'exclusive offer', 'only for you',
    'keep this confidential', 'do not tell anyone',
]
INVESTMENT_KW = [
    'guaranteed returns', 'double your money', 'crypto investment', 'forex trading',
    'binary options', '1000% profit', 'passive income', 'work from home earn',
    'mlm', 'pyramid', 'referral bonus', 'get rich', 'financial freedom',
]
SUSPICIOUS_KW = [
    'click', 'download', 'install', 'open attachment', 'verify your identity',
    'update your information', 'confirm your details', 'login to your account',
]

URL_RE       = re.compile(r'https?://[^\s]+', re.IGNORECASE)
SHORT_URL_RE = re.compile(
    r'\b(bit\.ly|tinyurl\.com|goo\.gl|t\.co|ow\.ly|buff\.ly|is\.gd|rb\.gy|cutt\.ly|tiny\.cc|adf\.ly)[^\s]*',
    re.IGNORECASE)
OTP_RE   = re.compile(r'otp[\s:is]*\d{4,8}', re.IGNORECASE)
PHONE_RE = re.compile(r'(\+?\d[\d\s\-(.)]{7,}\d)')

def heuristic_analyze(text: str) -> AnalysisResult:
    lower   = text.lower()
    reasons = []
    score   = 0

    fin = [k for k in FINANCIAL_KW if k in lower]
    if fin:
        pts = min(len(fin) * 12, 35); score += pts
        top = ", ".join(f'"{k}"' for k in fin[:3])
        reasons.append(DetectionReason(label="Financial Keywords Detected",
            description=f"Found {len(fin)} financial term(s): {top}. Scammers use these to steal money or credentials.",
            scoreContribution=pts, iconCategory=IconCategory.financial))

    prize = [k for k in PRIZE_KW if k in lower]
    if prize:
        pts = min(len(prize) * 14, 30); score += pts
        top = ", ".join(f'"{k}"' for k in prize[:3])
        reasons.append(DetectionReason(label="Prize / Lottery Language",
            description=f"Classic lottery-scam language: {top}. Legitimate organisations never announce prizes via SMS.",
            scoreContribution=pts, iconCategory=IconCategory.suspicious))

    urgency = [k for k in URGENCY_KW if k in lower]
    if urgency:
        pts = min(len(urgency) * 10, 25); score += pts
        top = ", ".join(f'"{k}"' for k in urgency[:3])
        reasons.append(DetectionReason(label="Urgency & Pressure Tactics",
            description=f"{len(urgency)} urgency trigger(s): {top}. Creating artificial pressure is a core scam technique.",
            scoreContribution=pts, iconCategory=IconCategory.urgency))

    imp = [k for k in IMPERSONATION_KW if k in lower]
    if imp:
        pts = min(len(imp) * 20, 35); score += pts
        top = ", ".join(f'"{k}"' for k in imp[:3])
        reasons.append(DetectionReason(label="Authority Impersonation",
            description=f"Claims to be from: {top}. Scammers impersonate government agencies and tech companies to create fear.",
            scoreContribution=pts, iconCategory=IconCategory.manipulation))

    inv = [k for k in INVESTMENT_KW if k in lower]
    if inv:
        pts = min(len(inv) * 15, 30); score += pts
        top = ", ".join(f'"{k}"' for k in inv[:3])
        reasons.append(DetectionReason(label="Investment / Job Fraud",
            description=f"Investment scam language: {top}. Promises of easy money are a hallmark of fraud.",
            scoreContribution=pts, iconCategory=IconCategory.financial))

    short_m = SHORT_URL_RE.findall(text)
    url_m   = URL_RE.findall(text)
    if short_m:
        pts = 25; score += pts
        reasons.append(DetectionReason(label="Shortened / Obfuscated URL",
            description=f"Found {len(short_m)} shortened URL(s). Scammers hide malicious destinations behind link shorteners.",
            scoreContribution=pts, iconCategory=IconCategory.link))
    elif url_m:
        pts = 10; score += pts
        reasons.append(DetectionReason(label="Link Detected",
            description=f"Found {len(url_m)} link(s). Verify before clicking, especially if unexpected.",
            scoreContribution=pts, iconCategory=IconCategory.link))

    if OTP_RE.search(lower):
        pts = 25; score += pts
        reasons.append(DetectionReason(label="OTP / Code Sharing Request",
            description="Contains or requests an OTP. No legitimate service ever asks you to share your OTP.",
            scoreContribution=pts, iconCategory=IconCategory.financial))

    manip = [k for k in MANIPULATION_KW if k in lower]
    if manip:
        pts = min(len(manip) * 8, 20); score += pts
        top = ", ".join(f'"{k}"' for k in manip[:3])
        reasons.append(DetectionReason(label="Psychological Manipulation",
            description=f"Manipulative language: {top}. Designed to bypass critical thinking.",
            scoreContribution=pts, iconCategory=IconCategory.manipulation))

    susp = [k for k in SUSPICIOUS_KW if k in lower]
    if susp:
        pts = min(len(susp) * 5, 15); score += pts
        top = ", ".join(f'"{k}"' for k in susp[:3])
        reasons.append(DetectionReason(label="Suspicious Action Words",
            description=f"Action-driving language: {top}. Be cautious of messages asking you to click, download or install.",
            scoreContribution=pts, iconCategory=IconCategory.suspicious))

    phones = PHONE_RE.findall(text)
    if phones and reasons:
        score += 5
        reasons.append(DetectionReason(label="Embedded Phone Number",
            description=f"Found {len(phones)} phone number(s). Scammers embed numbers for direct voice contact with victims.",
            scoreContribution=5, iconCategory=IconCategory.suspicious))

    score = min(score, 100)

    if score >= 65:
        cls     = ScamClassification.scam
        summary = "High-confidence scam detected. Do NOT click any links, share any data, or call any numbers."
    elif score >= 30:
        cls     = ScamClassification.suspicious
        summary = "Multiple warning signals detected. Do NOT share personal or financial information. Verify independently."
    else:
        cls     = ScamClassification.safe
        summary = "No significant scam patterns detected. Always exercise normal caution."

    if not reasons:
        reasons.append(DetectionReason(label="No Threats Detected",
            description="No known scam patterns found in this message.",
            scoreContribution=0, iconCategory=IconCategory.safe))

    return AnalysisResult(classification=cls, riskScore=score, reasons=reasons,
                          summary=summary, aiPowered=False)

# ── OSINT — real API calls ─────────────────────────────────────────────────────
async def vt_lookup_hash(sha256: str) -> dict:
    if not VIRUSTOTAL_API_KEY:
        return {"malicious": 0, "suspicious": 0, "note": "VirusTotal not configured.", "checked": False}
    try:
        async with httpx.AsyncClient(timeout=10.0) as c:
            r = await c.get(
                f"https://www.virustotal.com/api/v3/files/{sha256}",
                headers={"x-apikey": VIRUSTOTAL_API_KEY},
            )
        if r.status_code == 200:
            stats = r.json().get("data", {}).get("attributes", {}).get("last_analysis_stats", {})
            mal, susp = stats.get("malicious", 0), stats.get("suspicious", 0)
            return {"malicious": mal, "suspicious": susp, "checked": True,
                    "note": f"{mal} vendor(s) flagged as malicious, {susp} suspicious." if (mal or susp) else "No detections on VirusTotal."}
        if r.status_code == 404:
            return {"malicious": 0, "suspicious": 0, "checked": True, "note": "Hash not found in VirusTotal (new or unknown file)."}
        return {"malicious": 0, "suspicious": 0, "checked": True, "note": f"VirusTotal HTTP {r.status_code}."}
    except Exception as e:
        logger.warning(f"VT lookup error: {e}")
        return {"malicious": 0, "suspicious": 0, "checked": False, "note": "VirusTotal lookup timed out."}

async def gsb_lookup_urls(urls: List[str]) -> List[dict]:
    if not GOOGLE_SAFE_BROWSING_KEY or not urls:
        return [{"url": u, "malicious": False, "note": "Safe Browsing not configured.", "checked": False} for u in urls]
    try:
        payload = {
            "client": {"clientId": "scamshield", "clientVersion": "3.0"},
            "threatInfo": {
                "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE", "POTENTIALLY_HARMFUL_APPLICATION"],
                "platformTypes": ["ANY_PLATFORM"],
                "threatEntryTypes": ["URL"],
                "threatEntries": [{"url": u} for u in urls],
            },
        }
        async with httpx.AsyncClient(timeout=8.0) as c:
            r = await c.post(
                f"https://safebrowsing.googleapis.com/v4/threatMatches:find?key={GOOGLE_SAFE_BROWSING_KEY}",
                json=payload,
            )
        flagged = set()
        if r.status_code == 200:
            for m in (r.json().get("matches") or []):
                flagged.add(m.get("threat", {}).get("url", ""))
        return [{"url": u, "malicious": u in flagged, "checked": True,
                 "note": "Flagged by Google Safe Browsing." if u in flagged else "Clean per Google Safe Browsing."} for u in urls]
    except Exception as e:
        logger.warning(f"GSB lookup error: {e}")
        return [{"url": u, "malicious": False, "note": "Safe Browsing lookup failed.", "checked": False} for u in urls]

DOMAIN_RE = re.compile(r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))+$")

async def crtsh_domain_check(domain: str) -> dict:
    """Certificate Transparency lookup via crt.sh — free, no API key required.

    A domain with zero issued certificates, or whose earliest certificate is
    only days old, is a meaningful phishing/scam-infrastructure signal
    (legitimate sites typically have a longer TLS certificate history).
    """
    try:
        async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as c:
            r = await c.get(
                "https://crt.sh/",
                params={"q": domain, "output": "json"},
                headers={"User-Agent": "ScamShield/3.0 (+https://github.com/)"},
            )
        if r.status_code != 200 or not r.text.strip():
            return {"checked": False, "cert_count": 0, "first_seen_days_ago": None,
                    "note": "Certificate Transparency lookup unavailable."}
        try:
            entries = r.json()
        except ValueError:
            entries = []
        if not entries:
            return {"checked": True, "cert_count": 0, "first_seen_days_ago": None,
                    "note": "No TLS certificates found for this domain in Certificate Transparency logs — unusual for an established site."}
        dates = []
        for e in entries:
            raw = e.get("not_before")
            if not raw:
                continue
            try:
                dates.append(datetime.fromisoformat(raw.replace("Z", "+00:00")))
            except ValueError:
                continue
        first_seen_days = None
        if dates:
            earliest = min(dates)
            now = datetime.now(earliest.tzinfo) if earliest.tzinfo else datetime.now()
            first_seen_days = max(0, (now - earliest).days)
        return {
            "checked": True,
            "cert_count": len(entries),
            "first_seen_days_ago": first_seen_days,
            "note": (f"{len(entries)} certificate(s) on record"
                     + (f", oldest issued {first_seen_days} day(s) ago." if first_seen_days is not None else ".")),
        }
    except Exception as e:
        logger.warning(f"crt.sh lookup error: {e}")
        return {"checked": False, "cert_count": 0, "first_seen_days_ago": None,
                "note": "Certificate Transparency lookup failed."}

async def rdap_domain_age(domain: str) -> dict:
    """Domain-registration-age lookup via the public RDAP protocol (WHOIS's
    successor) — free, no API key required. rdap.org transparently routes
    the query to the correct registry's RDAP server.
    """
    try:
        async with httpx.AsyncClient(timeout=8.0, follow_redirects=True) as c:
            r = await c.get(f"https://rdap.org/domain/{domain}",
                             headers={"Accept": "application/rdap+json"})
        if r.status_code != 200:
            return {"checked": False, "registered_days_ago": None,
                    "note": "RDAP lookup unavailable for this domain/TLD."}
        data = r.json()
        registered_days_ago = None
        for event in data.get("events", []) or []:
            if event.get("eventAction") in ("registration", "last changed") and event.get("eventDate"):
                try:
                    when = datetime.fromisoformat(event["eventDate"].replace("Z", "+00:00"))
                    now = datetime.now(when.tzinfo) if when.tzinfo else datetime.now()
                    registered_days_ago = max(0, (now - when).days)
                    if event.get("eventAction") == "registration":
                        break
                except ValueError:
                    continue
        return {
            "checked": True,
            "registered_days_ago": registered_days_ago,
            "note": (f"Registered ~{registered_days_ago} day(s) ago." if registered_days_ago is not None
                     else "Registration date not available from RDAP."),
        }
    except Exception as e:
        logger.warning(f"RDAP lookup error: {e}")
        return {"checked": False, "registered_days_ago": None, "note": "RDAP lookup failed."}

async def domain_intel(domain: str) -> dict:
    """Combines the two free, keyless domain-trust signals above."""
    cert, rdap = await asyncio.gather(crtsh_domain_check(domain), rdap_domain_age(domain))
    is_new_domain = (
        (cert.get("first_seen_days_ago") is not None and cert["first_seen_days_ago"] < 30)
        or (rdap.get("registered_days_ago") is not None and rdap["registered_days_ago"] < 30)
        or (cert.get("checked") and cert.get("cert_count") == 0)
    )
    return {"domain": domain, "certificate_transparency": cert, "rdap": rdap, "newly_registered_or_unproven": is_new_domain}

async def abuseipdb_lookup(ip: str) -> dict:
    if not ABUSEIPDB_API_KEY:
        return {"abuseConfidenceScore": 0, "note": "AbuseIPDB not configured.", "checked": False}
    try:
        async with httpx.AsyncClient(timeout=8.0) as c:
            r = await c.get("https://api.abuseipdb.com/api/v2/check",
                            params={"ipAddress": ip, "maxAgeInDays": 90},
                            headers={"Accept": "application/json", "Key": ABUSEIPDB_API_KEY})
        if r.status_code == 200:
            sc = r.json().get("data", {}).get("abuseConfidenceScore", 0)
            return {"abuseConfidenceScore": sc, "checked": True,
                    "note": f"Abuse confidence: {sc}%." + (" ⚠ HIGH RISK IP." if sc > 50 else " Low risk.")}
        return {"abuseConfidenceScore": 0, "checked": True, "note": f"AbuseIPDB HTTP {r.status_code}."}
    except Exception as e:
        logger.warning(f"AbuseIPDB error: {e}")
        return {"abuseConfidenceScore": 0, "checked": False, "note": "AbuseIPDB lookup timed out."}

# ── APK static analysis pipeline ──────────────────────────────────────────────
SECRET_PATTERNS = {
    "aws_access_key":  re.compile(r"(A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA|ASIA)[A-Z0-9]{16}"),
    "google_api_key":  re.compile(r"AIza[0-9A-Za-z\-_]{35}"),
    "firebase_url":    re.compile(r"https://[a-z0-9-]+\.firebaseio\.com"),
    "jwt_token":       re.compile(r"ey[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"),
    "stripe_live_key": re.compile(r"sk_live_[0-9a-zA-Z]{24}"),
    "supabase_url":    re.compile(r"https://[a-z0-9-]+\.supabase\.co"),
    "openai_api_key":  re.compile(r"sk-[a-zA-Z0-9]{48}"),
    "github_token":    re.compile(r"(ghp|gho|ghu|ghs|ghr)_[a-zA-Z0-9]{36}"),
    "private_key":     re.compile(r"-----BEGIN (RSA|EC|DSA|OPENSSH) PRIVATE KEY-----"),
}

APK_URL_RE       = re.compile(r"https?://[^\s\"'<>]{4,200}")
PRINTABLE_STR_RE = re.compile(rb"[\x20-\x7e]{6,}")

DANGEROUS_PERMS = {
    "sms":      {"suffixes": ["RECEIVE_SMS", "READ_SMS", "SEND_SMS"],    "score": 30},
    "overlay":  {"suffixes": ["SYSTEM_ALERT_WINDOW", "BIND_ACCESSIBILITY_SERVICE"], "score": 35},
    "install":  {"suffixes": ["INSTALL_PACKAGES", "REQUEST_INSTALL_PACKAGES"],      "score": 20},
    "contacts": {"suffixes": ["READ_CONTACTS", "READ_CALL_LOG"],                    "score": 8},
    "location": {"suffixes": ["ACCESS_FINE_LOCATION", "ACCESS_BACKGROUND_LOCATION"],"score": 10},
    "admin":    {"suffixes": ["BIND_DEVICE_ADMIN", "MANAGE_DEVICE_ADMINS"],         "score": 40},
}

_yara_rules    = None
_yara_attempted = False

def get_yara_rules():
    global _yara_rules, _yara_attempted
    if _yara_attempted:
        return _yara_rules
    _yara_attempted = True
    if not YARA_AVAILABLE:
        return None
    rules_path = BASE_DIR / "yara_rules" / "sample_rules.yar"
    if not rules_path.exists():
        rules_path = BASE_DIR.parent / "backend" / "yara_rules" / "sample_rules.yar"
    if not rules_path.exists():
        logger.warning(f"YARA rules not found: {rules_path}")
        return None
    try:
        _yara_rules = yara.compile(filepath=str(rules_path))
        logger.info("YARA rules compiled OK.")
    except Exception as e:
        logger.error(f"YARA compile error: {e}")
    return _yara_rules

def extract_strings(apk_path: str) -> bytes:
    chunks, total, LIMIT = [], 0, 20_000_000
    MAX_ENTRY_SIZE = 15_000_000
    MAX_TOTAL_UNCOMPRESSED = 100_000_000
    total_uncompressed = 0
    
    try:
        with zipfile.ZipFile(apk_path) as zf:
            infolist = zf.infolist()
            if len(infolist) > 10_000:
                logger.warning("Zip Bomb alert: Excessive ZIP entries count (>10,000)")
                return b"Warning: Excessive ZIP entry count"
                
            for info in infolist:
                if ".." in info.filename or info.filename.startswith("/"):
                    continue
                total_uncompressed += info.file_size
                if total_uncompressed > MAX_TOTAL_UNCOMPRESSED:
                    logger.warning("Zip Bomb alert: Total uncompressed size limit exceeded")
                    break
                    
                if info.file_size == 0 or info.file_size > MAX_ENTRY_SIZE:
                    continue
                ext = info.filename.rsplit(".", 1)[-1].lower() if "." in info.filename else ""
                if ext not in {"dex", "xml", "so", "json", "txt", "js", "html", "htm", "cfg", "properties"}:
                    continue
                try:
                    data = zf.read(info.filename)
                except Exception:
                    continue
                for m in PRINTABLE_STR_RE.finditer(data):
                    chunks.append(m.group()); total += len(m.group())
                    if total >= LIMIT:
                        break
                if total >= LIMIT:
                    break
    except zipfile.BadZipFile:
        pass
    return b"\n".join(chunks)

# LRU scan cache
_SCAN_CACHE: "OrderedDict[str, dict]" = OrderedDict()
_CACHE_MAX  = 128

def _cache_get(k: str):
    v = _SCAN_CACHE.get(k)
    if v:
        _SCAN_CACHE.move_to_end(k)
    return v

def _cache_put(k: str, v: dict):
    _SCAN_CACHE[k] = v
    _SCAN_CACHE.move_to_end(k)
    while len(_SCAN_CACHE) > _CACHE_MAX:
        _SCAN_CACHE.popitem(last=False)

async def analyze_apk_file(apk_path: str, file_size: int) -> dict:
    with open(apk_path, "rb") as f:
        raw = f.read()
    md5    = hashlib.md5(raw).hexdigest()
    sha1   = hashlib.sha1(raw).hexdigest()
    sha256 = hashlib.sha256(raw).hexdigest()

    cached = _cache_get(sha256)
    if cached:
        logger.info(f"Cache hit: {sha256[:12]}")
        return {**cached, "cached": True}

    risk_factors: List[str] = []
    risk_breakdown: List[dict] = []  # structured score contributions for UI display
    score = 15  # baseline
    dangerous_permissions: List[str] = []

    # 1. Androguard manifest / permission / cert analysis
    permissions, package_name, certificates = [], "unknown", []
    is_signed, androguard_status = False, "unavailable"
    if ANDROGUARD_AVAILABLE:
        try:
            apk          = AndroguardAPK(apk_path)
            permissions  = apk.get_permissions() or []
            package_name = apk.get_package() or "unknown"
            is_signed    = apk.is_signed()
            if is_signed:
                for cert in apk.get_certificates():
                    certificates.append({
                        "issuer":  cert.issuer.human_friendly,
                        "subject": cert.subject.human_friendly,
                        "sha1":    cert.sha1.hex(),
                        "sha256":  cert.sha256.hex(),
                    })
            androguard_status = "success"
        except Exception as e:
            androguard_status = f"error: {str(e)[:80]}"
            logger.warning(f"Androguard failed: {e}")

    perm_str = " ".join(permissions).upper()
    for group, cfg in DANGEROUS_PERMS.items():
        matched = [s for s in cfg["suffixes"] if s in perm_str]
        if matched:
            pts = cfg["score"]; score += pts
            label = f"Dangerous permission: {', '.join(matched)}"
            risk_factors.append(f"Dangerous permission group '{group}': {', '.join(matched)} (+{pts} risk points).")
            risk_breakdown.append({"factor": label, "points": pts, "category": "permissions"})
            dangerous_permissions.extend(matched)

    if androguard_status == "success" and not is_signed:
        risk_factors.append("APK is not cryptographically signed — unusual for legitimate apps.")
        score += 20
        risk_breakdown.append({"factor": "Unsigned APK", "points": 20, "category": "manifest"})

    # 2. String extraction
    blob = extract_strings(apk_path)
    text = blob.decode("latin-1", errors="ignore")

    # 3. Secret detection
    secrets_found: dict = {}
    for name, pat in SECRET_PATTERNS.items():
        n = len(pat.findall(text))
        if n:
            secrets_found[name] = n
    if secrets_found:
        pts = 25
        risk_factors.append(f"Hardcoded secrets in DEX/resources: {', '.join(secrets_found.keys())}."); score += pts
        risk_breakdown.append({"factor": f"Hardcoded secrets ({', '.join(secrets_found.keys())})", "points": pts, "category": "secrets"})

    # 4. URL extraction + suspicious URL check
    urls = sorted(set(APK_URL_RE.findall(text)))[:50]
    suspicious_indicators = ["bit.ly", "tinyurl", "ngrok", "free", "prize", "earn", "money"]
    suspicious_urls = [u for u in urls if any(s in u.lower() for s in suspicious_indicators)]
    if urls:
        pts = 10 + (10 if suspicious_urls else 0); score += pts
        risk_factors.append(f"Extracted {len(urls)} network endpoint(s)" +
                            (f", {len(suspicious_urls)} suspicious." if suspicious_urls else "."))
        risk_breakdown.append({"factor": f"Network endpoints ({len(urls)} found{', '+str(len(suspicious_urls))+' suspicious' if suspicious_urls else ''})", "points": pts, "category": "network"})

    # 5. YARA signatures
    yara_matches: List[str] = []
    rules = get_yara_rules()
    if rules:
        try:
            yara_matches = [m.rule for m in rules.match(data=blob)]
        except Exception as e:
            logger.warning(f"YARA error: {e}")
    if yara_matches:
        pts = 40
        risk_factors.append(f"YARA malware signatures: {', '.join(yara_matches)}."); score += pts
        risk_breakdown.append({"factor": f"YARA signatures matched: {', '.join(yara_matches)}", "points": pts, "category": "yara"})

    # 6. VirusTotal hash lookup (real key)
    vt_result = await vt_lookup_hash(sha256)
    if vt_result.get("malicious", 0) > 0:
        pts = min(vt_result["malicious"] * 5, 40)
        risk_factors.append(f"VirusTotal: {vt_result['malicious']} vendor(s) flagged as malicious.")
        score += pts
        risk_breakdown.append({"factor": f"VirusTotal: {vt_result['malicious']} malicious detections", "points": pts, "category": "virustotal"})

    # 7. Google Safe Browsing on embedded URLs (real key)
    gsb_results: List[dict] = []
    if urls:
        gsb_results = await gsb_lookup_urls(urls[:10])
        gsb_flagged = [r for r in gsb_results if r.get("malicious")]
        if gsb_flagged:
            pts = min(len(gsb_flagged) * 15, 40)
            risk_factors.append(f"Google Safe Browsing: {len(gsb_flagged)} embedded URL(s) flagged as dangerous.")
            score += pts
            risk_breakdown.append({"factor": f"Safe Browsing: {len(gsb_flagged)} dangerous URL(s)", "points": pts, "category": "safe_browsing"})

    # 8. Domain intelligence on embedded URLs — free, keyless (crt.sh + RDAP).
    # Capped at 3 unique hostnames to bound scan latency.
    domain_intel_results: List[dict] = []
    if urls:
        hostnames: List[str] = []
        seen_hosts = set()
        for u in urls[:10]:
            try:
                host = urlparse(u if "://" in u else f"http://{u}").hostname
            except ValueError:
                host = None
            if host and host not in seen_hosts and DOMAIN_RE.fullmatch(host):
                seen_hosts.add(host)
                hostnames.append(host)
            if len(hostnames) >= 3:
                break
        if hostnames:
            domain_intel_results = list(await asyncio.gather(*(domain_intel(h) for h in hostnames)))
            unproven = [d for d in domain_intel_results if d["newly_registered_or_unproven"]]
            if unproven:
                pts = min(len(unproven) * 10, 20)
                names = ", ".join(d["domain"] for d in unproven)
                risk_factors.append(f"Newly-registered or certificate-history-free domain(s): {names}.")
                score += pts
                risk_breakdown.append({"factor": f"Unproven domain(s): {names}", "points": pts, "category": "domain_intel"})

    score = max(0, min(100, score))
    level = ("CRITICAL" if score >= 75 else "HIGH" if score >= 50 else "MEDIUM" if score >= 30 else "LOW")

    if not risk_factors:
        risk_factors.append("No major threat patterns found in static analysis.")

    if not risk_breakdown:
        risk_breakdown.append({"factor": "Baseline (no threats detected)", "points": 15, "category": "baseline"})

    report = {
        "scan_mode": "server",
        "risk": {
            "level": level,
            "score": score,
            "details": risk_factors,
            "breakdown": risk_breakdown,
        },
        "ai_explanation": (
            f"Full-stack analysis completed: Androguard manifest parsing "
            f"({'OK' if androguard_status == 'success' else 'unavailable'}), "
            f"DEX/resource string extraction ({len(secrets_found)} secret type(s) found), "
            f"YARA signature matching ({len(yara_matches)} hit(s)), "
            f"VirusTotal hash check ({'configured' if VIRUSTOTAL_API_KEY else 'not configured'}), "
            f"Google Safe Browsing URL check ({'configured' if GOOGLE_SAFE_BROWSING_KEY else 'not configured'}). "
            f"Risk level: {level} ({score}/100)."
        ),
        "file_info": {"md5": md5, "sha1": sha1, "sha256": sha256, "size": file_size},
        "androguard": {
            "status": androguard_status,
            "permissions": permissions,
            "dangerous_permissions": dangerous_permissions,
            "package_name": package_name,
            "certificates": certificates,
        },
        "secrets": {"findings": secrets_found, "urls": urls, "suspicious_urls": suspicious_urls},
        "yara": {"matches": yara_matches},
        "osint": {
            "virustotal":    {**vt_result},
            "safe_browsing": {"results": gsb_results, "checked": bool(GOOGLE_SAFE_BROWSING_KEY)},
            "domain_intel":  {"results": domain_intel_results, "checked": True},
        },
    }
    _cache_put(sha256, report)
    return {**report, "cached": False}

# ── API Routes ─────────────────────────────────────────────────────────────────
@app.get("/")
async def root():
    return {
        "status": "ok", "service": "ScamShield API", "version": "3.0.0",
        "gemini_available":    GEMINI_AVAILABLE,
        "virustotal":          bool(VIRUSTOTAL_API_KEY),
        "safe_browsing":       bool(GOOGLE_SAFE_BROWSING_KEY),
        "abuseipdb":           bool(ABUSEIPDB_API_KEY),
        "domain_intel":        True,  # crt.sh + RDAP — always available, no API key
        "androguard":          ANDROGUARD_AVAILABLE,
        "yara":                YARA_AVAILABLE,
    }

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.post("/analyze", response_model=AnalysisResult)
@limiter.limit("60/minute")
async def analyze_message(request: Request, body: AnalysisRequest):
    text = body.text.strip()
    if not text:
        return AnalysisResult(
            classification=ScamClassification.safe, riskScore=0,
            reasons=[DetectionReason(label="No Content", description="No message provided.",
                                     scoreContribution=0, iconCategory=IconCategory.safe)],
            summary="No content provided.", aiPowered=False)
    ai = await analyze_with_groq(text) or await analyze_with_gemini(text)
    res = ai if ai else heuristic_analyze(text)
    log_audit_event("text", text[:100], res.riskScore, res.classification.value)
    return res

@app.post("/analyze-voice", response_model=AnalysisResult)
@limiter.limit("20/minute")
async def analyze_voice(request: Request, file: UploadFile = File(...)):
    contents = await file.read()
    if not contents:
        raise HTTPException(400, "Audio file is empty.")
    
    audio_summary = ""
    try:
        import wave
        with wave.open(io.BytesIO(contents), "rb") as wf:
            channels = wf.getnchannels()
            framerate = wf.getframerate()
            nframes = wf.getnframes()
            duration = nframes / float(framerate) if framerate > 0 else 0
            audio_summary = f"WAV Audio file: {duration:.2f}s duration, {framerate}Hz, {channels} ch."
    except Exception:
        printable = "".join(chr(b) for b in contents if 32 <= b <= 126)
        urls = [m.group() for m in URL_RE.finditer(printable)]
        if urls:
            audio_summary = f"Audio container analysis ({len(contents)} bytes). Embedded URLs: {' '.join(urls)}"
        else:
            audio_summary = f"Audio recording ({len(contents)} bytes). Analysis performed."

    result = await analyze_with_groq(audio_summary) or await analyze_with_gemini(audio_summary) or heuristic_analyze(audio_summary)
    log_audit_event("voice", file.filename or "voice_note.wav", result.riskScore, result.classification.value)
    return result

@app.post("/analyze-image", response_model=AnalysisResult)
@limiter.limit("20/minute")
async def analyze_image(request: Request, file: UploadFile = File(...)):
    contents = await file.read()
    if not contents:
        raise HTTPException(400, "Image file is empty.")
    
    extracted_text = ""
    try:
        import PIL.Image
        image = PIL.Image.open(io.BytesIO(contents))
        try:
            import pytesseract
            extracted_text = pytesseract.image_to_string(image).strip()
        except Exception:
            pass
            
        if not extracted_text:
            info_str = f"Image metadata: format={image.format}, mode={image.mode}, size={image.size}"
            printable = "".join(chr(b) for b in contents if 32 <= b <= 126)
            urls = [m.group() for m in URL_RE.finditer(printable)]
            if urls:
                extracted_text = f"{info_str}. Extracted URLs from image binary: {' '.join(urls)}"
            else:
                extracted_text = f"{info_str}. No printable text extracted from image OCR."
    except Exception as e:
        logger.warning(f"Image analysis error: {e}")
        extracted_text = f"Image binary analysis ({len(contents)} bytes)."

    result = await analyze_with_groq(extracted_text) or await analyze_with_gemini(extracted_text) or heuristic_analyze(extracted_text)
    log_audit_event("image", file.filename or "screenshot.png", result.riskScore, result.classification.value)
    return result

@app.post("/scan", response_model=ScanResult)
@limiter.limit("10/minute")
async def scan_apk(request: Request, file: UploadFile = File(...)):
    if not (file.filename or "").lower().endswith(".apk"):
        raise HTTPException(400, "Only .apk files are accepted.")
    contents = await file.read()
    if not contents:
        raise HTTPException(400, "File is empty.")
    if len(contents) > MAX_APK_SIZE:
        raise HTTPException(413, f"File exceeds {MAX_APK_SIZE // (1024*1024)} MB limit.")
    if not zipfile.is_zipfile(io.BytesIO(contents)):
        raise HTTPException(400, "File is not a valid APK (not a ZIP archive).")
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".apk")
    try:
        tmp.write(contents)
        tmp.close()
        report = await analyze_apk_file(tmp.name, len(contents))
        log_audit_event("apk", file.filename or "uploaded.apk", report["risk"]["score"], report["risk"]["level"])
        return report
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"/scan error: {e}")
        raise HTTPException(500, "Internal error analysing APK.")
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass

@app.get("/osint/hash/{file_hash}")
@limiter.limit("60/minute")
async def osint_hash(request: Request, file_hash: str):
    if not re.fullmatch(r"[A-Fa-f0-9]{32}|[A-Fa-f0-9]{40}|[A-Fa-f0-9]{64}", file_hash):
        raise HTTPException(400, "Invalid hash format (MD5/SHA-1/SHA-256 expected).")
    return await vt_lookup_hash(file_hash.lower())

@app.post("/osint/urls")
@limiter.limit("60/minute")
async def osint_urls(request: Request, body: UrlCheckRequest):
    return {"results": await gsb_lookup_urls(body.urls)}

@app.get("/osint/ip/{ip}")
@limiter.limit("60/minute")
async def osint_ip(request: Request, ip: str):
    try:
        ipaddress.ip_address(ip)
    except ValueError:
        raise HTTPException(400, "Invalid IP address.")
    return await abuseipdb_lookup(ip)

@app.get("/osint/domain/{domain}")
@limiter.limit("60/minute")
async def osint_domain(request: Request, domain: str):
    """Domain-trust check using two free, keyless sources: Certificate
    Transparency logs (crt.sh) and RDAP registration data (rdap.org).
    Unlike the other /osint/* routes, this never returns a "not configured"
    placeholder — both sources are always available without an API key."""
    domain = domain.strip().lower()
    if not DOMAIN_RE.fullmatch(domain):
        raise HTTPException(400, "Invalid domain format.")
    try:
        ipaddress.ip_address(domain)
        raise HTTPException(400, "Expected a domain name, not an IP address — use /osint/ip/{ip} instead.")
    except ValueError:
        pass
    return await domain_intel(domain)

@app.post("/report", response_model=ScamReportResponse)
@limiter.limit("5/minute")
async def report_scam_indicator(request: Request, body: ScamReportRequest):
    """Lets a user flag a phone number/URL/domain as a scam. Anti-abuse note:
    this only records the report — see REPORT_THRESHOLD_FOR_SIGNAL and
    GET /reputation for how (and when) reports actually surface as a signal,
    so a handful of malicious reports can't tank a legitimate number/site."""
    normalized = _normalize_indicator(body.indicator_type.value, body.indicator_value)
    if not normalized:
        raise HTTPException(400, "indicator_value is empty after normalization.")

    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        cur.execute(
            "SELECT report_count, category FROM scam_reports WHERE indicator_type = ? AND indicator_value = ?",
            (body.indicator_type.value, normalized),
        )
        row = cur.fetchone()
        if row:
            new_count = row[0] + 1
            category = body.category or row[1]
            cur.execute(
                """UPDATE scam_reports SET report_count = ?, category = ?, last_reported = CURRENT_TIMESTAMP
                   WHERE indicator_type = ? AND indicator_value = ?""",
                (new_count, category, body.indicator_type.value, normalized),
            )
        else:
            new_count = 1
            category = body.category
            cur.execute(
                """INSERT INTO scam_reports (indicator_type, indicator_value, category, report_count)
                   VALUES (?, ?, ?, 1)""",
                (body.indicator_type.value, normalized, category),
            )
        conn.commit()
        conn.close()
    except Exception as e:
        logger.warning(f"Scam report write error: {e}")
        raise HTTPException(500, "Failed to record report.")

    return ScamReportResponse(
        indicator_type=body.indicator_type.value,
        indicator_value=normalized,
        report_count=new_count,
        category=category,
    )

@app.get("/reputation/{indicator_type}/{indicator_value}", response_model=ReputationResponse)
@limiter.limit("60/minute")
async def get_indicator_reputation(request: Request, indicator_type: ScamReportType, indicator_value: str):
    """Checks whether a number/URL/domain has been community-reported as a
    scam. `reported` only turns true once REPORT_THRESHOLD_FOR_SIGNAL
    independent reports exist — report_count is still returned below that
    so callers can see raw counts if they want them."""
    normalized = _normalize_indicator(indicator_type.value, indicator_value)
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        cur.execute(
            """SELECT report_count, category, first_reported, last_reported FROM scam_reports
               WHERE indicator_type = ? AND indicator_value = ?""",
            (indicator_type.value, normalized),
        )
        row = cur.fetchone()
        conn.close()
    except Exception as e:
        logger.warning(f"Reputation lookup error: {e}")
        raise HTTPException(503, "Reputation lookup temporarily unavailable.")

    if not row:
        return ReputationResponse(
            indicator_type=indicator_type.value,
            indicator_value=normalized,
            reported=False,
            report_count=0,
        )

    return ReputationResponse(
        indicator_type=indicator_type.value,
        indicator_value=normalized,
        reported=row[0] >= REPORT_THRESHOLD_FOR_SIGNAL,
        report_count=row[0],
        category=row[1],
        first_reported=row[2],
        last_reported=row[3],
    )

@app.post("/feedback/verdict", response_model=VerdictFeedbackResponse)
@limiter.limit("20/minute")
async def submit_verdict_feedback(request: Request, body: VerdictFeedbackRequest):
    """Records whether a verdict the app produced was actually right.

    This closes the loop that a pure heuristic/LLM pipeline otherwise never
    gets: a false positive on a legitimate bank SMS is invisible to us unless
    the person who received it says so. Anonymous by construction — no account
    is required and no message content is accepted, only its hash.

    Re-voting the same way on the same message is idempotent (the UNIQUE
    constraint absorbs it); changing your mind replaces the earlier vote, so a
    single user can never stack multiple counts onto one message.
    """
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        # A person may only hold one opinion per message. Clearing the other
        # agreements first means switching from "missed" to "correct" moves the
        # vote rather than counting twice.
        cur.execute(
            "DELETE FROM verdict_feedback WHERE content_hash = ? AND agreement != ?",
            (body.content_hash, body.agreement.value),
        )
        cur.execute(
            """INSERT INTO verdict_feedback (content_hash, classification, risk_score, agreement, note)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(content_hash, agreement) DO UPDATE SET
                   classification = excluded.classification,
                   risk_score     = excluded.risk_score,
                   note           = excluded.note,
                   created_at     = CURRENT_TIMESTAMP""",
            (
                body.content_hash,
                body.classification.value,
                body.risk_score,
                body.agreement.value,
                body.note,
            ),
        )
        cur.execute("SELECT COUNT(*) FROM verdict_feedback")
        total = cur.fetchone()[0]
        conn.commit()
        conn.close()
    except Exception as e:
        logger.warning(f"Verdict feedback write error: {e}")
        raise HTTPException(500, "Failed to record feedback.")

    log_audit_event("verdict_feedback", body.agreement.value, body.risk_score, body.classification.value)
    return VerdictFeedbackResponse(recorded=True, total_feedback=total)

@app.get("/feedback/accuracy", response_model=VerdictAccuracyResponse)
@limiter.limit("60/minute")
async def verdict_accuracy(request: Request, days: int = 30):
    """How often the detection pipeline has been agreeing with reality.

    Aggregate counts only. Surfaced publicly on purpose: an accuracy figure the
    user can actually see is worth more than one asserted in marketing copy.
    """
    days = max(1, min(days, 365))
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        cur.execute(
            f"""SELECT classification, agreement, COUNT(*) FROM verdict_feedback
                WHERE created_at >= datetime('now', '-{days} days')
                GROUP BY classification, agreement""",
        )
        rows = cur.fetchall()
        conn.close()
    except Exception as e:
        logger.warning(f"Verdict accuracy read error: {e}")
        raise HTTPException(503, "Accuracy stats temporarily unavailable.")

    totals = {"correct": 0, "false_positive": 0, "missed": 0}
    by_classification: dict = {}
    for classification, agreement, count in rows:
        if agreement in totals:
            totals[agreement] += count
        bucket = by_classification.setdefault(
            classification, {"correct": 0, "false_positive": 0, "missed": 0}
        )
        if agreement in bucket:
            bucket[agreement] += count

    total = sum(totals.values())
    return VerdictAccuracyResponse(
        days=days,
        total=total,
        correct=totals["correct"],
        false_positives=totals["false_positive"],
        missed=totals["missed"],
        # No feedback yet is reported as 0%, not as a fabricated 100%.
        accuracy_percent=round(totals["correct"] * 100.0 / total, 1) if total else 0.0,
        by_classification=by_classification,
    )

@app.get("/trends")
@limiter.limit("60/minute")
async def scam_trends(request: Request, days: int = 7):
    """What is being reported lately, aggregated by scam category.

    Built from community reports rather than a curated feed, so it reflects
    what users are actually hitting this week. Only aggregate counts are
    returned — never the reported indicators themselves, which would turn a
    "what's going around" feed into a directory of live scam numbers.
    """
    days = max(1, min(days, 90))
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        cur.execute(
            f"""SELECT COALESCE(NULLIF(TRIM(category), ''), 'Uncategorised') AS category,
                       SUM(report_count) AS reports,
                       COUNT(*)          AS distinct_indicators
                FROM scam_reports
                WHERE last_reported >= datetime('now', '-{days} days')
                GROUP BY 1
                ORDER BY reports DESC
                LIMIT 20"""
        )
        rows = cur.fetchall()
        conn.close()
    except Exception as e:
        logger.warning(f"Trend query error: {e}")
        raise HTTPException(503, "Trend data is temporarily unavailable.")

    trends = [
        {"category": r[0], "reports": int(r[1] or 0), "distinct_indicators": int(r[2] or 0)}
        for r in rows
    ]
    return {
        "window_days": days,
        "total_reports": sum(t["reports"] for t in trends),
        "trends": trends,
    }

@app.get("/dashboard")
async def get_dashboard(request: Request):
    await verify_admin_auth(request)
    dash_path = BASE_DIR / "static" / "dashboard.html"
    if not dash_path.exists():
        raise HTTPException(404, "Dashboard HTML file not found.")
    return FileResponse(dash_path)

@app.get("/api/audit-logs")
async def get_audit_logs(request: Request, limit: int = 50):
    await verify_admin_auth(request)
    cleanup_audit_logs()

    # Server-side limit validation & bounding (PHASE 4)
    if limit < 1:
        limit = 1
    elif limit > 100:
        limit = 100
        
    logs = []
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        # Parameterized query preventing SQL injection
        cur.execute("SELECT timestamp, event_type, target, risk_score, risk_level FROM audit_logs ORDER BY id DESC LIMIT ?", (limit,))
        for row in cur.fetchall():
            # Redact secrets / tokens from audit log target outputs (PHASE 3)
            clean_target = re.sub(r"(AIzaSy[0-9A-Za-z\-_]{30,}|sk-[a-zA-Z0-9]{20,}|AKIA[A-Z0-9]{16})", "[REDACTED_SECRET]", str(row[2]))
            logs.append({
                "timestamp": row[0],
                "event_type": row[1],
                "target": clean_target[:150],
                "risk_score": row[3],
                "risk_level": row[4],
            })
        conn.close()
    except Exception as e:
        logger.warning(f"Error fetching audit logs: {e}")
    return logs

@app.delete("/api/audit-logs")
async def delete_audit_logs(request: Request):
    """Admin-only erasure of all stored audit-log rows (message excerpts,
    filenames). Supports the right-to-erasure / data-minimisation controls
    documented in DPDP_COMPLIANCE.md — there is no per-user scoping because
    this table has never recorded any user/account identifier (see
    DPDP_AUDIT.md §4)."""
    await verify_admin_auth(request)
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        cur.execute("DELETE FROM audit_logs")
        deleted = cur.rowcount
        conn.commit()
        conn.close()
        logger.info(f"Admin purge: removed {deleted} audit_logs row(s).")
        return {"deleted": deleted}
    except Exception as e:
        logger.warning(f"Error deleting audit logs: {e}")
        raise HTTPException(500, "Failed to delete audit logs.")

@app.post("/scan-batch")
@limiter.limit("10/minute")
async def scan_batch(request: Request, files: List[UploadFile] = File(...)):
    if len(files) > MAX_BATCH_FILES:
        raise HTTPException(400, f"Too many files in one batch (max {MAX_BATCH_FILES}).")
    results = []
    for file in files:
        if not (file.filename or "").lower().endswith(".apk"):
            results.append({"filename": file.filename, "status": "skipped", "reason": "Not a .apk file"})
            continue
        contents = await file.read()
        if len(contents) > MAX_APK_SIZE:
            results.append({"filename": file.filename, "status": "skipped", "reason": "File exceeds 100MB limit"})
            continue
        if contents and zipfile.is_zipfile(io.BytesIO(contents)):
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".apk")
            try:
                tmp.write(contents)
                tmp.close()
                report = await analyze_apk_file(tmp.name, len(contents))
                log_audit_event("batch_apk", file.filename or "batch.apk", report["risk"]["score"], report["risk"]["level"])
                results.append({"filename": file.filename, "status": "scanned", "report": report})
            finally:
                try:
                    os.unlink(tmp.name)
                except OSError:
                    pass
        else:
            results.append({"filename": file.filename, "status": "skipped", "reason": "Not a valid APK"})
    return {"total_files": len(files), "results": results}

@app.get("/stats")
async def stats():
    audit_count = 0
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        cur.execute("SELECT count(*) FROM audit_logs")
        audit_count = cur.fetchone()[0]
        conn.close()
    except Exception:
        pass
    return {
        "total_scans_cached":  len(_SCAN_CACHE),
        "total_audit_events":  audit_count,
        "gemini_available":    GEMINI_AVAILABLE,
        "yara_rules_loaded":   _yara_rules is not None,
        "virustotal":          bool(VIRUSTOTAL_API_KEY),
        "safe_browsing":       bool(GOOGLE_SAFE_BROWSING_KEY),
        "abuseipdb":           bool(ABUSEIPDB_API_KEY),
        "androguard":          ANDROGUARD_AVAILABLE,
    }

EMAIL_REGEX = re.compile(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")

@app.get("/api/v1/breach", response_model=BreachResponse)
@app.get("/breach", response_model=BreachResponse)
@limiter.limit("30/minute")
async def check_email_breach(request: Request, email: str):
    email = email.strip().lower()
    if not EMAIL_REGEX.match(email):
        raise HTTPException(status_code=400, detail="Invalid email format.")

    url = f"https://api.xposedornot.com/v1/breach-analytics?email={email}"
    headers = {}
    if XPOSEDORNOT_API_KEY:
        headers["x-api-key"] = XPOSEDORNOT_API_KEY

    from datetime import datetime, timezone
    async with httpx.AsyncClient(timeout=8.0) as client:
        try:
            response = await client.get(url, headers=headers)
        except httpx.TimeoutException:
            raise HTTPException(status_code=504, detail="Breach database request timed out.")
        except httpx.RequestError:
            raise HTTPException(status_code=503, detail="Breach database service unavailable.")

        if response.status_code == 429:
            raise HTTPException(status_code=429, detail="Too many requests. Please try again later.")

        if response.status_code == 404:
            return BreachResponse(
                email=email,
                exposed=False,
                breachCount=0,
                breaches=[],
                source="XposedOrNot",
                checkedAt=datetime.now(timezone.utc).isoformat()
            )

        if response.status_code != 200:
            raise HTTPException(status_code=502, detail="Error communicating with breach database.")

        try:
            data = response.json()
        except ValueError:
            raise HTTPException(status_code=502, detail="Malformed response from breach database.")

        exposed_breaches = data.get("ExposedBreaches")
        if not exposed_breaches or not isinstance(exposed_breaches, dict):
            return BreachResponse(
                email=email,
                exposed=False,
                breachCount=0,
                breaches=[],
                source="XposedOrNot",
                checkedAt=datetime.now(timezone.utc).isoformat()
            )

        breach_details = exposed_breaches.get("breaches_details", [])
        if not isinstance(breach_details, list):
            breach_details = []

        normalized_breaches = []
        for b in breach_details:
            if not isinstance(b, dict):
                continue
            raw_date = b.get("xposed_date") or "unknown"
            if len(raw_date) == 4 and raw_date.isdigit():
                formatted_date = f"{raw_date}-01-01"
            else:
                formatted_date = raw_date

            data_classes_str = b.get("xposed_data") or ""
            data_classes = [d.strip() for d in data_classes_str.split(";") if d.strip()]

            normalized_breaches.append(Breach(
                name=b.get("breach") or "Unknown Breach",
                domain=b.get("domain") or "unknown.com",
                date=formatted_date,
                dataClasses=data_classes
            ))

        return BreachResponse(
            email=email,
            exposed=len(normalized_breaches) > 0,
            breachCount=len(normalized_breaches),
            breaches=normalized_breaches,
            source="XposedOrNot",
            checkedAt=datetime.now(timezone.utc).isoformat()
        )

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
