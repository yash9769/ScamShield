"""
backend/app/services/heuristic_service.py
Advanced keyword-based heuristic engine for scam detection.
Runs synchronously and is always available as a fallback.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import List

from app.models.enums import IconCategory, ScamCategory, ScamClassification
from app.schemas.response import DetectionReason

# ── Keyword dictionaries ──────────────────────────────────────────────────────

FINANCIAL_KW = frozenset({
    "bank", "account", "otp", "pin", "password", "credit card", "debit card",
    "transaction", "transfer", "wire", "payment", "wallet", "kyc",
    "verify your account", "aadhaar", "pan card", "upi", "ifsc", "cvv",
    "neft", "rtgs", "net banking", "atm", "swift", "iban", "routing number",
    "bank details", "account number", "card number", "expiry",
})

PRIZE_KW = frozenset({
    "win", "winner", "lottery", "prize", "reward", "congratulations", "selected",
    "gift card", "voucher", "free money", "jackpot", "lucky draw", "cash prize",
    "you have been chosen", "claim your prize", "you are the winner",
})

URGENCY_KW = frozenset({
    "urgent", "immediately", "act now", "limited time", "expires", "final notice",
    "last chance", "within 24 hours", "suspended", "blocked", "terminated",
    "action required", "verify now", "confirm now", "do not ignore", "deadline",
    "your account will be", "will be closed", "within hours", "respond immediately",
})

MANIPULATION_KW = frozenset({
    "click here", "click now", "tap here", "do not share", "never share",
    "call us immediately", "call now", "trust us", "guaranteed", "risk free",
    "no cost", "secret", "confidential", "exclusive offer", "only for you",
    "do not tell anyone", "keep this private",
})

SUSPICIOUS_KW = frozenset({
    "click", "download", "install", "open attachment", "verify your identity",
    "update your information", "confirm your details", "login to your account",
    "access your account", "secure your account",
})

CRYPTO_KW = frozenset({
    "bitcoin", "btc", "ethereum", "eth", "crypto", "nft", "blockchain",
    "wallet address", "send crypto", "crypto investment", "double your bitcoin",
    "mining reward", "crypto giveaway", "defi", "usdt", "binance",
})

GOVERNMENT_KW = frozenset({
    "income tax", "income tax department", "itat", "cbdt", "ird",
    "government of india", "ministry of", "police", "court notice",
    "arrest warrant", "fir", "cybercrime", "enforcement directorate",
    "customs", "immigration", "visa", "passport",
})

ROMANCE_KW = frozenset({
    "i love you", "i miss you", "i need your help", "send me money",
    "trapped", "stranded", "emergency", "sick relative", "hospital",
    "flight ticket", "visa fee", "gift to you", "beautiful relationship",
    "we met online", "military deployed", "oil rig",
})

JOB_KW = frozenset({
    "work from home", "part time job", "earn money online", "easy money",
    "data entry job", "no experience required", "daily payment",
    "registration fee", "training fee", "job guarantee", "hiring now urgent",
})

COURIER_KW = frozenset({
    "package held", "parcel blocked", "customs fee", "delivery fee",
    "your order is held", "pay to release", "shipment on hold",
    "delivery pending", "dhl", "fedex scam", "india post notice",
})

# ── Regex patterns ─────────────────────────────────────────────────────────────

URL_RE = re.compile(r"https?://[^\s]+", re.IGNORECASE)
SHORT_URL_RE = re.compile(
    r"\b(bit\.ly|tinyurl\.com|goo\.gl|t\.co|ow\.ly|buff\.ly|is\.gd|"
    r"rb\.gy|cutt\.ly|tiny\.cc|adf\.ly|shorturl\.at|clck\.ru)[^\s]*",
    re.IGNORECASE,
)
OTP_RE = re.compile(r"\botp\b[\s:is]*\d{4,8}", re.IGNORECASE)
PHONE_RE = re.compile(r"(\+?\d[\d\s\-(.)]{7,}\d)")
UPI_RE = re.compile(r"[a-zA-Z0-9.\-_]+@[a-zA-Z0-9]+", re.IGNORECASE)
QR_RE = re.compile(r"\bqr\s*(code)?\b", re.IGNORECASE)
AMOUNT_RE = re.compile(r"(rs\.?|inr|₹|\$)\s*[\d,]+", re.IGNORECASE)


@dataclass
class HeuristicResult:
    """Raw output from the heuristic engine before score aggregation."""

    score: int = 0
    reasons: List[DetectionReason] = field(default_factory=list)
    detected_category: ScamCategory = ScamCategory.unknown
    classification: ScamClassification = ScamClassification.safe


# ── Engine ─────────────────────────────────────────────────────────────────────

class HeuristicService:
    """
    Keyword and pattern-based scam detection engine.

    Always returns a result — never raises exceptions.
    Used as the primary fallback when Gemini is unavailable,
    and also to provide a secondary signal for score aggregation.
    """

    def analyze(self, text: str) -> HeuristicResult:
        """Run heuristic analysis on the given text and return a HeuristicResult."""
        lower = text.lower()
        reasons: List[DetectionReason] = []
        score = 0
        category_votes: dict[ScamCategory, int] = {}

        def vote(cat: ScamCategory, pts: int) -> None:
            category_votes[cat] = category_votes.get(cat, 0) + pts

        # ── Financial keywords ─────────────────────────────────────────────────
        fin_hits = [k for k in FINANCIAL_KW if k in lower]
        if fin_hits:
            pts = min(len(fin_hits) * 12, 35)
            score += pts
            top = ", ".join(f'"{k}"' for k in fin_hits[:3])
            reasons.append(DetectionReason(
                label="Financial Keywords",
                description=f"Detected {len(fin_hits)} sensitive financial term(s): {top}. "
                            "Scammers use these to steal financial information.",
                scoreContribution=pts,
                iconCategory=IconCategory.financial,
            ))
            vote(ScamCategory.bank_scam, pts)

        # ── Prize / Lottery ────────────────────────────────────────────────────
        prize_hits = [k for k in PRIZE_KW if k in lower]
        if prize_hits:
            pts = min(len(prize_hits) * 14, 30)
            score += pts
            top = ", ".join(f'"{k}"' for k in prize_hits[:3])
            reasons.append(DetectionReason(
                label="Prize / Lottery Language",
                description=f"Classic lottery-scam language detected: {top}. "
                            "Legitimate organisations never announce prizes via SMS or email.",
                scoreContribution=pts,
                iconCategory=IconCategory.suspicious,
            ))
            vote(ScamCategory.lottery_scam, pts)

        # ── Urgency ────────────────────────────────────────────────────────────
        urgency_hits = [k for k in URGENCY_KW if k in lower]
        if urgency_hits:
            pts = min(len(urgency_hits) * 10, 25)
            score += pts
            top = ", ".join(f'"{k}"' for k in urgency_hits[:3])
            reasons.append(DetectionReason(
                label="Urgency & Pressure Tactics",
                description=f"{len(urgency_hits)} urgency trigger(s) found: {top}. "
                            "Creating artificial pressure is a core scam technique.",
                scoreContribution=pts,
                iconCategory=IconCategory.urgency,
            ))

        # ── Shortened URL ──────────────────────────────────────────────────────
        short_matches = SHORT_URL_RE.findall(text)
        url_matches = URL_RE.findall(text)
        if short_matches:
            pts = 25
            score += pts
            reasons.append(DetectionReason(
                label="Suspicious Shortened URL",
                description=f"Found {len(short_matches)} shortened URL(s). "
                            "Scammers hide malicious destinations behind URL shorteners.",
                scoreContribution=pts,
                iconCategory=IconCategory.link,
            ))
            vote(ScamCategory.phishing, pts)
        elif url_matches:
            pts = 10
            score += pts
            reasons.append(DetectionReason(
                label="External Link Detected",
                description=f"Found {len(url_matches)} link(s). "
                            "Verify any link independently before clicking.",
                scoreContribution=pts,
                iconCategory=IconCategory.link,
            ))

        # ── OTP request ────────────────────────────────────────────────────────
        if OTP_RE.search(lower) or ("otp" in lower and any(w in lower for w in ["share", "send", "give", "enter"])):
            pts = 25
            score += pts
            reasons.append(DetectionReason(
                label="OTP / Code Request",
                description="The message contains or requests an OTP. "
                            "No legitimate service ever asks you to share your OTP.",
                scoreContribution=pts,
                iconCategory=IconCategory.financial,
            ))
            vote(ScamCategory.otp_scam, pts)

        # ── Manipulation ───────────────────────────────────────────────────────
        manip_hits = [k for k in MANIPULATION_KW if k in lower]
        if manip_hits:
            pts = min(len(manip_hits) * 8, 20)
            score += pts
            top = ", ".join(f'"{k}"' for k in manip_hits[:3])
            reasons.append(DetectionReason(
                label="Psychological Manipulation",
                description=f"Manipulative language detected: {top}. "
                            "Scammers use these phrases to bypass critical thinking.",
                scoreContribution=pts,
                iconCategory=IconCategory.manipulation,
            ))

        # ── Crypto keywords ────────────────────────────────────────────────────
        crypto_hits = [k for k in CRYPTO_KW if k in lower]
        if crypto_hits:
            pts = min(len(crypto_hits) * 12, 30)
            score += pts
            top = ", ".join(f'"{k}"' for k in crypto_hits[:3])
            reasons.append(DetectionReason(
                label="Cryptocurrency / Investment Scam",
                description=f"Crypto-related terms found: {top}. "
                            "Crypto giveaway and doubling schemes are always scams.",
                scoreContribution=pts,
                iconCategory=IconCategory.crypto,
            ))
            vote(ScamCategory.investment_scam, pts)

        # ── Government impersonation ───────────────────────────────────────────
        gov_hits = [k for k in GOVERNMENT_KW if k in lower]
        if gov_hits:
            pts = min(len(gov_hits) * 10, 28)
            score += pts
            top = ", ".join(f'"{k}"' for k in gov_hits[:3])
            reasons.append(DetectionReason(
                label="Government Impersonation",
                description=f"Government-related terms: {top}. "
                            "Scammers impersonate authorities to create fear and compliance.",
                scoreContribution=pts,
                iconCategory=IconCategory.government,
            ))
            vote(ScamCategory.government_scam, pts)

        # ── Romance scam ───────────────────────────────────────────────────────
        romance_hits = [k for k in ROMANCE_KW if k in lower]
        if romance_hits:
            pts = min(len(romance_hits) * 11, 28)
            score += pts
            top = ", ".join(f'"{k}"' for k in romance_hits[:3])
            reasons.append(DetectionReason(
                label="Romance Scam Signals",
                description=f"Emotional manipulation language: {top}. "
                            "These are hallmarks of romance and advance-fee scams.",
                scoreContribution=pts,
                iconCategory=IconCategory.romance,
            ))
            vote(ScamCategory.romance_scam, pts)

        # ── Job scam ──────────────────────────────────────────────────────────
        job_hits = [k for k in JOB_KW if k in lower]
        if job_hits:
            pts = min(len(job_hits) * 10, 25)
            score += pts
            top = ", ".join(f'"{k}"' for k in job_hits[:3])
            reasons.append(DetectionReason(
                label="Fake Job Offer",
                description=f"Suspicious job-related keywords: {top}. "
                            "Legitimate employers never ask for registration or training fees.",
                scoreContribution=pts,
                iconCategory=IconCategory.job,
            ))
            vote(ScamCategory.job_scam, pts)

        # ── Courier / delivery scam ────────────────────────────────────────────
        courier_hits = [k for k in COURIER_KW if k in lower]
        if courier_hits:
            pts = min(len(courier_hits) * 10, 22)
            score += pts
            top = ", ".join(f'"{k}"' for k in courier_hits[:2])
            reasons.append(DetectionReason(
                label="Fake Delivery / Courier Scam",
                description=f"Package scam language detected: {top}. "
                            "Legitimate couriers do not demand payment via SMS or links.",
                scoreContribution=pts,
                iconCategory=IconCategory.suspicious,
            ))
            vote(ScamCategory.courier_scam, pts)

        # ── UPI / QR code ──────────────────────────────────────────────────────
        if UPI_RE.search(text) and fin_hits:
            pts = 15
            score += pts
            reasons.append(DetectionReason(
                label="UPI / Payment Request",
                description="A UPI ID is present alongside financial keywords. "
                            "Scammers use UPI for untraceable money transfer.",
                scoreContribution=pts,
                iconCategory=IconCategory.financial,
            ))
            vote(ScamCategory.upi_scam, pts)

        if QR_RE.search(lower) and score > 20:
            pts = 12
            score += pts
            reasons.append(DetectionReason(
                label="QR Code Reference",
                description="Message references a QR code while showing other scam signals. "
                            "Fake QR codes redirect to phishing or payment sites.",
                scoreContribution=pts,
                iconCategory=IconCategory.suspicious,
            ))
            vote(ScamCategory.fake_qr_scam, pts)

        # ── Phone number (amplifier) ───────────────────────────────────────────
        phone_matches = PHONE_RE.findall(text)
        if phone_matches and reasons:
            pts = 5
            score += pts
            reasons.append(DetectionReason(
                label="Embedded Phone Number",
                description=f"Found {len(phone_matches)} phone number(s). "
                            "Combined with other signals, this may indicate a vishing attempt.",
                scoreContribution=pts,
                iconCategory=IconCategory.suspicious,
            ))

        # ── Suspicious action words ────────────────────────────────────────────
        susp_hits = [k for k in SUSPICIOUS_KW if k in lower]
        if susp_hits:
            pts = min(len(susp_hits) * 5, 15)
            score += pts
            top = ", ".join(f'"{k}"' for k in susp_hits[:3])
            reasons.append(DetectionReason(
                label="Suspicious Action Words",
                description=f"Action-driving language found: {top}. "
                            "Be cautious of messages urging you to click, download, or install.",
                scoreContribution=pts,
                iconCategory=IconCategory.suspicious,
            ))

        # ── Clamp score ────────────────────────────────────────────────────────
        score = max(0, min(100, score))

        # ── Determine category from votes ──────────────────────────────────────
        detected_category = ScamCategory.unknown
        if category_votes:
            detected_category = max(category_votes, key=lambda c: category_votes[c])

        # ── Classification ─────────────────────────────────────────────────────
        if score == 0:
            classification = ScamClassification.safe
            detected_category = ScamCategory.safe
            reasons.append(DetectionReason(
                label="No Threats Detected",
                description="This message does not contain known scam patterns, "
                            "urgency tactics, suspicious links, or financial data requests.",
                scoreContribution=0,
                iconCategory=IconCategory.safe,
            ))
        elif score < 30:
            classification = ScamClassification.safe
        elif score < 65:
            classification = ScamClassification.suspicious
        else:
            classification = ScamClassification.scam

        return HeuristicResult(
            score=score,
            reasons=reasons,
            detected_category=detected_category,
            classification=classification,
        )
