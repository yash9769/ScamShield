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
    "you won", "kbc",
})

URGENCY_KW = frozenset({
    "urgent", "immediately", "act now", "limited time", "expires", "final notice",
    "last chance", "within 24 hours", "suspended", "blocked", "terminated",
    "action required", "verify now", "confirm now", "do not ignore", "deadline",
    "your account will be", "will be closed", "within hours", "respond immediately",
})

MANIPULATION_KW = frozenset({
    # Not "do not share" / "never share": that is the warning every genuine
    # bank OTP SMS carries, and counting it flagged real OTPs as suspicious.
    "click here", "click now", "tap here",
    "call us immediately", "call now", "trust us", "guaranteed", "risk free",
    "no cost", "secret", "confidential", "exclusive offer", "only for you",
    "do not tell anyone", "keep this private",
})

SUSPICIOUS_KW = frozenset({
    "click", "download", "install", "open attachment", "verify your identity",
    "update your information", "confirm your details", "login to your account",
    "access your account", "secure your account",
    "via the link", "link below", "following link",
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
# Asking for the code, as opposed to delivering it. "Share OTP 482913 with
# our agent" is a request; "Your OTP is 551203. Do not share it" is a bank
# delivering a code and warning you, and must not score as a scam.
OTP_REQUEST_RE = re.compile(
    r"\b(share|send|tell|forward|give|provide|read\s+out|reply\s+with)\b[^.]{0,40}\b(otp|code|pin)\b"
    r"|\b(otp|code)\b[^.]{0,30}\b(to|with)\s+(our|the|this)\s+(agent|executive|officer|representative|number)\b",
    re.IGNORECASE,
)
NEGATION_RE = re.compile(r"\b(never|not|don't|dont|do\s+not)\s*$", re.IGNORECASE)
# Threats to cut a service off: the electricity / SIM / gas bill scam.
DISCONNECTION_RE = re.compile(
    r"\b(electricity|power|light|gas|water|connection|sim|mobile number|number|service)\b[^.]{0,50}"
    r"\b(disconnect\w*|cut\s+off|deactivat\w*|be\s+blocked|suspend\w*)\b"
    r"|\b(disconnect\w*|deactivat\w*)\b[^.]{0,40}\b(tonight|today|within)\b",
    re.IGNORECASE,
)
# Money demanded up front to release a prize, loan, parcel or job.
ADVANCE_FEE_RE = re.compile(
    r"\b(processing|registration|clearance|release|delivery|activation|verification|customs)\s+(fee|fees|charge|charges)\b"
    r"|\b(pay|deposit|transfer|send)\b[^.]{0,30}\b(fee|charges?|tax)\b[^.]{0,30}\b(to\s+)?(claim|release|receive|activate|unlock)\b",
    re.IGNORECASE,
)


def keyword_hits(keywords, lower: str) -> list[str]:
    """Whole-word matches only, in a stable order: a substring test let "pin"
    fire inside "shipping" and "win" inside "window"."""
    return [k for k in sorted(keywords)
            if re.search(r"(?<![a-z0-9])" + re.escape(k) + r"(?![a-z0-9])", lower)]


def asks_for_otp(text: str) -> bool:
    """True when the message asks for a code, ignoring negated forms like
    "never share this code" that genuine OTP messages use as a warning."""
    for m in OTP_REQUEST_RE.finditer(text):
        if not NEGATION_RE.search(text[max(0, m.start() - 12):m.start()]):
            return True
    return False


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
        fin_hits = keyword_hits(FINANCIAL_KW, lower)
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
        prize_hits = keyword_hits(PRIZE_KW, lower)
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
        urgency_hits = keyword_hits(URGENCY_KW, lower)
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
        if asks_for_otp(text):
            pts = 30
            score += pts
            reasons.append(DetectionReason(
                label="OTP / Code Request",
                description="The message asks you to share an OTP or code. "
                            "No legitimate service ever asks you to share your OTP.",
                scoreContribution=pts,
                iconCategory=IconCategory.financial,
            ))
            vote(ScamCategory.otp_scam, pts)
        elif OTP_RE.search(lower) and (url_matches or short_matches):
            # A code delivered alongside a link. A code delivered on its own,
            # with no request, is the normal shape of a genuine OTP: no points.
            pts = 15
            score += pts
            reasons.append(DetectionReason(
                label="OTP Alongside a Link",
                description="An OTP arrives together with a link. "
                            "Never enter a code on a page reached from a message.",
                scoreContribution=pts,
                iconCategory=IconCategory.financial,
            ))
            vote(ScamCategory.otp_scam, pts)

        # ── Service disconnection threat ───────────────────────────────────────
        if DISCONNECTION_RE.search(text):
            pts = 30
            score += pts
            reasons.append(DetectionReason(
                label="Service Disconnection Threat",
                description="Threatens to cut off your electricity, SIM or another service unless you act now. "
                            "Utilities don't disconnect over SMS; check with the provider's official number.",
                scoreContribution=pts,
                iconCategory=IconCategory.urgency,
            ))
            vote(ScamCategory.bank_scam, pts)

        # ── Upfront fee demand ─────────────────────────────────────────────────
        if ADVANCE_FEE_RE.search(text):
            pts = 30
            score += pts
            reasons.append(DetectionReason(
                label="Upfront Fee Demand",
                description="Asks for a fee before you can receive a prize, loan, parcel or job. "
                            "Real prizes and refunds never require paying first.",
                scoreContribution=pts,
                iconCategory=IconCategory.financial,
            ))
            vote(ScamCategory.lottery_scam if keyword_hits(PRIZE_KW, lower) else ScamCategory.job_scam, pts)

        # ── Manipulation ───────────────────────────────────────────────────────
        manip_hits = keyword_hits(MANIPULATION_KW, lower)
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
        crypto_hits = keyword_hits(CRYPTO_KW, lower)
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
        gov_hits = keyword_hits(GOVERNMENT_KW, lower)
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
        romance_hits = keyword_hits(ROMANCE_KW, lower)
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
        job_hits = keyword_hits(JOB_KW, lower)
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
        courier_hits = keyword_hits(COURIER_KW, lower)
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
        susp_hits = keyword_hits(SUSPICIOUS_KW, lower)
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
