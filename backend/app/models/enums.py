"""
backend/app/models/enums.py
All application-level enumerations for ScamShield.
"""

from __future__ import annotations

from enum import Enum


class ScamClassification(str, Enum):
    """Final verdict for a piece of content."""

    safe = "safe"
    suspicious = "suspicious"
    scam = "scam"


class ScamCategory(str, Enum):
    """Detailed scam category classification."""

    phishing = "Phishing"
    upi_scam = "UPI Scam"
    job_scam = "Job Scam"
    investment_scam = "Investment Scam"
    lottery_scam = "Lottery Scam"
    otp_scam = "OTP Scam"
    courier_scam = "Courier Scam"
    government_scam = "Government Scam"
    bank_scam = "Bank Scam"
    romance_scam = "Romance Scam"
    fake_qr_scam = "Fake QR Scam"
    unknown = "Unknown"
    safe = "Safe"


class IconCategory(str, Enum):
    """Icon category for UI display of detection reasons."""

    financial = "financial"
    link = "link"
    urgency = "urgency"
    suspicious = "suspicious"
    manipulation = "manipulation"
    safe = "safe"
    government = "government"
    romance = "romance"
    crypto = "crypto"
    job = "job"


class AnalysisSource(str, Enum):
    """Which engine produced the primary analysis result."""

    gemini = "gemini"
    heuristic = "heuristic"
    hybrid = "hybrid"


class RecommendedAction(str, Enum):
    """Actionable recommendation for the end user."""

    no_action = "No action required. Message appears safe."
    be_cautious = "Be cautious. Verify the sender before responding."
    do_not_respond = "Do NOT respond. Block and report this message."
    block_and_report = "Block the sender immediately and report to authorities."
