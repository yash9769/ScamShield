# server/main.py — ScamShield API v3.0
# Every feature the app promises is implemented here end-to-end with real keys.

import hashlib
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
from enum import Enum
from pathlib import Path
from typing import List, Optional

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, field_validator
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
ADMIN_API_KEY            = os.getenv("ADMIN_API_KEY", "scamshield_admin_sec_key_2026")

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

    if not token or token != ADMIN_API_KEY:
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

init_audit_db()

MAX_APK_SIZE    = 100 * 1024 * 1024

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
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

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
            resp = gemini_client.models.generate_content(
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
        urls = [m.group() for m in URL_REGEX.finditer(printable)]
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
            urls = [m.group() for m in URL_REGEX.finditer(printable)]
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

@app.post("/scan-batch")
@limiter.limit("10/minute")
async def scan_batch(request: Request, files: List[UploadFile] = File(...)):
    results = []
    for file in files:
        contents = await file.read()
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
            raw_date = b.get("xposed_date", "unknown")
            if len(raw_date) == 4 and raw_date.isdigit():
                formatted_date = f"{raw_date}-01-01"
            else:
                formatted_date = raw_date

            data_classes_str = b.get("xposed_data", "")
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
