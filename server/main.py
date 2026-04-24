# server/main.py — ScamShield V1 Backend (Hybrid AI + Heuristic Fallback)

import os
import json
import re
from typing import List
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from enum import Enum
from dotenv import load_dotenv

# ── Load environment ──────────────────────────────────────────────────────────
load_dotenv()
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")

# Try to import google-genai (new SDK)
try:
    from google import genai
    from google.genai import types as genai_types
    if GEMINI_API_KEY:
        gemini_client = genai.Client(api_key=GEMINI_API_KEY)
    else:
        gemini_client = None
    GEMINI_AVAILABLE = True
    print("[ScamShield] google-genai SDK loaded.")
except ImportError:
    gemini_client = None
    GEMINI_AVAILABLE = False
    print("[ScamShield] google-genai not found. Running in heuristic-only mode.")

# ── App setup ─────────────────────────────────────────────────────────────────
app = FastAPI(title="ScamShield API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Pydantic models ───────────────────────────────────────────────────────────
class ScamClassification(str, Enum):
    safe = "safe"
    suspicious = "suspicious"
    scam = "scam"

class IconCategory(str, Enum):
    financial = "financial"
    link = "link"
    urgency = "urgency"
    suspicious = "suspicious"
    manipulation = "manipulation"
    safe = "safe"

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

# ── Gemini System Prompt ──────────────────────────────────────────────────────
SYSTEM_PROMPT = """You are ScamShield AI, an elite cybersecurity analyst specializing in detecting digital scams, phishing, fraud, and social engineering attacks.

Analyze the provided message and return ONLY a valid JSON object with EXACTLY this structure:
{
  "classification": "safe" | "suspicious" | "scam",
  "riskScore": <integer 0-100>,
  "reasons": [
    {
      "label": "<Short category label, max 5 words>",
      "description": "<Detailed explanation. Be specific about what you found.>",
      "scoreContribution": <integer 0-40>,
      "iconCategory": "financial" | "link" | "urgency" | "suspicious" | "manipulation" | "safe"
    }
  ],
  "summary": "<1-2 sentence verdict. Be direct and actionable.>"
}

Classification:
- "safe" → riskScore 0-30. No real threat signals.
- "suspicious" → riskScore 31-65. Some red flags but not conclusive.
- "scam" → riskScore 66-100. Clear scam indicators.

Look for: OTP/PIN requests, phishing URLs, fake prize/lottery wins, urgency/pressure tactics, impersonation of banks/government, requests for financial info (UPI/KYC/Aadhaar/PAN), psychological manipulation (fear, greed), shortened links (bit.ly, tinyurl), poor grammar typical of scams.

If safe: give one reason with iconCategory "safe" explaining it looks legitimate.
Return ONLY the raw JSON. No markdown. No explanation."""

GEMINI_MODELS = [
    "gemini-2.0-flash",
    "gemini-2.0-flash-lite",
]

# ── JSON extractor ────────────────────────────────────────────────────────────
def extract_json(text: str) -> dict:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError:
            pass
    match = re.search(r"\{[\s\S]*\}", text)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass
    raise ValueError(f"Could not parse JSON from response: {text[:200]}")

# ── Gemini AI analysis ────────────────────────────────────────────────────────
async def analyze_with_gemini(text: str) -> AnalysisResult | None:
    if not gemini_client:
        return None

    for model_name in GEMINI_MODELS:
        try:
            response = gemini_client.models.generate_content(
                model=model_name,
                contents=f"Analyze this message:\n\n{text}",
                config=genai_types.GenerateContentConfig(
                    system_instruction=SYSTEM_PROMPT,
                    response_mime_type="application/json",
                    temperature=0.1,
                ),
            )
            result_data = extract_json(response.text)
            result_data["riskScore"] = max(0, min(100, int(result_data.get("riskScore", 0))))
            result_data["aiPowered"] = True

            valid_categories = {c.value for c in IconCategory}
            for reason in result_data.get("reasons", []):
                if reason.get("iconCategory") not in valid_categories:
                    reason["iconCategory"] = "suspicious"

            return AnalysisResult(**result_data)
        except Exception as e:
            err = str(e)
            print(f"[ScamShield] {model_name} failed: {err[:120]}")
            if "RESOURCE_EXHAUSTED" in err or "QUOTA" in err.upper():
                continue  # Try next model
            elif "NOT_FOUND" in err or "404" in err:
                continue  # Try next model
            else:
                print(f"[ScamShield] Unexpected error, falling back to heuristic.")
                return None

    print("[ScamShield] All Gemini models exhausted quota. Using heuristic fallback.")
    return None

# ── Heuristic fallback (Advanced keyword engine) ──────────────────────────────
FINANCIAL_KW = ['bank', 'account', 'otp', 'pin', 'password', 'credit card', 'debit card',
                  'transaction', 'transfer', 'wire', 'payment', 'wallet', 'kyc',
                  'verify your account', 'aadhaar', 'pan card', 'upi', 'ifsc', 'cvv',
                  'neft', 'rtgs', 'net banking', 'atm']
PRIZE_KW = ['win', 'winner', 'lottery', 'prize', 'reward', 'congratulations', 'selected',
             'gift card', 'voucher', 'free money', 'jackpot', 'lucky draw', 'cash prize']
URGENCY_KW = ['urgent', 'immediately', 'act now', 'limited time', 'expires', 'final notice',
               'last chance', 'within 24 hours', 'suspended', 'blocked', 'terminated',
               'action required', 'verify now', 'confirm now', 'do not ignore', 'deadline']
MANIPULATION_KW = ['click here', 'click now', 'tap here', 'do not share', 'never share',
                    'call us immediately', 'call now', 'trust us', 'guaranteed', 'risk free',
                    'no cost', 'secret', 'confidential', 'exclusive offer']
SUSPICIOUS_KW = ['click', 'download', 'install', 'open attachment', 'verify your identity',
                  'update your information', 'confirm your details']

URL_RE = re.compile(r'https?://[^\s]+', re.IGNORECASE)
SHORT_URL_RE = re.compile(
    r'\b(bit\.ly|tinyurl\.com|goo\.gl|t\.co|ow\.ly|buff\.ly|is\.gd|rb\.gy|cutt\.ly|tiny\.cc|adf\.ly)[^\s]*',
    re.IGNORECASE)
OTP_RE = re.compile(r'otp[\s:is]*\d{4,8}', re.IGNORECASE)
PHONE_RE = re.compile(r'(\+?\d[\d\s\-(.)]{7,}\d)')

def heuristic_analyze(text: str) -> AnalysisResult:
    lower = text.lower()
    reasons = []
    score = 0

    fin_hits = [k for k in FINANCIAL_KW if k in lower]
    if fin_hits:
        pts = min(len(fin_hits) * 12, 35)
        score += pts
        top = ', '.join('"' + k + '"' for k in fin_hits[:3])
        reasons.append(DetectionReason(
            label="Financial Keywords",
            description=f"Detected {len(fin_hits)} sensitive financial term(s): {top}. Scammers use these to steal financial information.",
            scoreContribution=pts, iconCategory=IconCategory.financial))

    prize_hits = [k for k in PRIZE_KW if k in lower]
    if prize_hits:
        pts = min(len(prize_hits) * 14, 30)
        score += pts
        top = ', '.join('"' + k + '"' for k in prize_hits[:3])
        reasons.append(DetectionReason(
            label="Prize / Lottery Language",
            description=f"Classic lottery-scam language detected: {top}. Legitimate organisations never announce prizes via SMS or email.",
            scoreContribution=pts, iconCategory=IconCategory.suspicious))

    urgency_hits = [k for k in URGENCY_KW if k in lower]
    if urgency_hits:
        pts = min(len(urgency_hits) * 10, 25)
        score += pts
        top = ', '.join('"' + k + '"' for k in urgency_hits[:3])
        reasons.append(DetectionReason(
            label="Urgency & Pressure Tactics",
            description=f"{len(urgency_hits)} urgency trigger(s) found: {top}. Creating artificial pressure is a core scam technique.",
            scoreContribution=pts, iconCategory=IconCategory.urgency))

    short_matches = SHORT_URL_RE.findall(text)
    url_matches = URL_RE.findall(text)
    if short_matches:
        pts = 25
        score += pts
        reasons.append(DetectionReason(
            label="Suspicious Shortened URL",
            description=f"Found {len(short_matches)} shortened URL(s). Scammers use URL shorteners to hide malicious destinations from victims.",
            scoreContribution=pts, iconCategory=IconCategory.link))
    elif url_matches:
        pts = 10
        score += pts
        reasons.append(DetectionReason(
            label="External Link Detected",
            description=f"Found {len(url_matches)} link(s). Verify any link independently before clicking, especially if unexpected.",
            scoreContribution=pts, iconCategory=IconCategory.link))

    if OTP_RE.search(lower):
        pts = 20
        score += pts
        reasons.append(DetectionReason(
            label="OTP / Code Request",
            description="The message contains or requests an OTP. No legitimate service ever asks you to share your OTP with anyone.",
            scoreContribution=pts, iconCategory=IconCategory.financial))

    manip_hits = [k for k in MANIPULATION_KW if k in lower]
    if manip_hits:
        pts = min(len(manip_hits) * 8, 20)
        score += pts
        top = ', '.join('"' + k + '"' for k in manip_hits[:3])
        reasons.append(DetectionReason(
            label="Psychological Manipulation",
            description=f"Manipulative language detected: {top}. Scammers use these phrases to bypass critical thinking.",
            scoreContribution=pts, iconCategory=IconCategory.manipulation))

    susp_hits = [k for k in SUSPICIOUS_KW if k in lower]
    if susp_hits:
        pts = min(len(susp_hits) * 5, 15)
        score += pts
        top = ', '.join('"' + k + '"' for k in susp_hits[:3])
        reasons.append(DetectionReason(
            label='Suspicious Action Words',
            description=f"Action-driving language found: {top}. Be cautious of messages urging you to click, download, or install.",
            scoreContribution=pts, iconCategory=IconCategory.suspicious))

    phone_matches = PHONE_RE.findall(text)
    if phone_matches and reasons:
        pts = 5
        score += pts
        reasons.append(DetectionReason(
            label="Embedded Phone Number",
            description=f"Found {len(phone_matches)} phone number(s). Combined with other signals, this suggests a vishing (voice phishing) attempt.",
            scoreContribution=pts, iconCategory=IconCategory.suspicious))

    score = max(0, min(100, score))

    if score == 0:
        classification = ScamClassification.safe
        summary = "No suspicious patterns were detected. This message appears to be safe."
        reasons.append(DetectionReason(
            label="No Threats Detected",
            description="This message does not contain known scam patterns, urgency tactics, suspicious links, or financial data requests.",
            scoreContribution=0, iconCategory=IconCategory.safe))
    elif score < 30:
        classification = ScamClassification.safe
        summary = "A few low-risk signals found. Exercise normal caution but no immediate threat detected."
    elif score < 65:
        classification = ScamClassification.suspicious
        summary = "Multiple warning signals detected. Do NOT share personal or financial information. Verify the sender independently."
    else:
        classification = ScamClassification.scam
        summary = "HIGH CONFIDENCE SCAM. This message uses classic social engineering tactics. Do not click any links, call any numbers, or share any data."

    return AnalysisResult(
        classification=classification,
        riskScore=score,
        reasons=reasons,
        summary=summary,
        aiPowered=False,
    )

# ── Routes ────────────────────────────────────────────────────────────────────
@app.get("/")
async def root():
    return {"status": "ok", "service": "ScamShield API", "version": "1.0.0",
            "gemini_available": GEMINI_AVAILABLE}

@app.get("/health")
async def health():
    return {"status": "healthy"}

@app.post("/analyze", response_model=AnalysisResult)
async def analyze_message(request: AnalysisRequest):
    text = request.text.strip()
    if not text:
        return AnalysisResult(
            classification=ScamClassification.safe, riskScore=0,
            reasons=[DetectionReason(label="No Content", description="No message was provided.",
                                     scoreContribution=0, iconCategory=IconCategory.safe)],
            summary="No content provided.", aiPowered=False)

    # 1. Try Gemini AI first
    ai_result = await analyze_with_gemini(text)
    if ai_result:
        return ai_result

    # 2. Fallback to advanced heuristic engine
    return heuristic_analyze(text)


if __name__ == "__main__":
    import uvicorn
    print("ScamShield API starting on http://0.0.0.0:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=False)
