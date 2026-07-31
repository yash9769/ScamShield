"""
backend/tests/unit/test_heuristic.py
Unit tests for the heuristic scam detection engine.
"""

from __future__ import annotations

import pytest

from app.models.enums import ScamCategory, ScamClassification
from app.services.heuristic_service import HeuristicService


@pytest.fixture
def engine() -> HeuristicService:
    return HeuristicService()


class TestHeuristicSafeMessages:
    def test_empty_ish_message_is_safe(self, engine):
        result = engine.analyze("Hello, how are you?")
        assert result.classification == ScamClassification.safe
        assert result.score == 0

    def test_normal_business_message(self, engine):
        result = engine.analyze("Your order has been shipped. Track at amazon.in/orders")
        assert result.classification in (ScamClassification.safe, ScamClassification.suspicious)

    def test_appointment_reminder(self, engine):
        result = engine.analyze("Reminder: Your appointment is scheduled for Monday at 10am.")
        assert result.classification == ScamClassification.safe
        assert result.score < 30

    def test_friend_message(self, engine):
        result = engine.analyze("Hey are you free this weekend for the cricket match?")
        assert result.classification == ScamClassification.safe


class TestHeuristicScamMessages:
    def test_otp_request_detected(self, engine):
        result = engine.analyze("Please share your OTP 123456 with our agent to verify your account.")
        assert result.score >= 25
        labels = [r.label for r in result.reasons]
        assert any("OTP" in label for label in labels)

    def test_bank_scam_detected(self, engine):
        result = engine.analyze(
            "Your SBI bank account has been suspended. "
            "Verify your KYC and share your ATM PIN to restore access."
        )
        assert result.classification in (ScamClassification.suspicious, ScamClassification.scam)
        assert result.score >= 30

    def test_lottery_scam_detected(self, engine):
        result = engine.analyze(
            "Congratulations! You are the winner of Rs 10 lakh in our lucky draw. "
            "Claim your prize within 24 hours."
        )
        assert result.classification in (ScamClassification.suspicious, ScamClassification.scam)
        assert result.score >= 30

    def test_shortened_url_detected(self, engine):
        result = engine.analyze("Click here to claim your reward: bit.ly/abc123xyz")
        labels = [r.label for r in result.reasons]
        assert any("Shortened" in label or "URL" in label for label in labels)
        assert result.score >= 25

    def test_urgency_keywords_detected(self, engine):
        result = engine.analyze(
            "URGENT: Action required immediately! Your account will be terminated "
            "within 24 hours. Do not ignore this final notice."
        )
        labels = [r.label for r in result.reasons]
        assert any("Urgency" in label for label in labels)

    def test_crypto_scam_detected(self, engine):
        result = engine.analyze(
            "Double your Bitcoin in 48 hours! Send USDT to earn guaranteed crypto returns. "
            "Exclusive DeFi opportunity."
        )
        labels = [r.label for r in result.reasons]
        assert any("Crypto" in label or "Investment" in label for label in labels)

    def test_government_impersonation(self, engine):
        result = engine.analyze(
            "Income Tax Department notice. An arrest warrant has been issued against you. "
            "Pay outstanding dues immediately to avoid FIR."
        )
        labels = [r.label for r in result.reasons]
        assert any("Government" in label for label in labels)

    def test_romance_scam_detected(self, engine):
        result = engine.analyze(
            "I love you. I am stranded in hospital abroad. Send me money for flight ticket. "
            "We met online and I need your help urgently."
        )
        labels = [r.label for r in result.reasons]
        assert any("Romance" in label for label in labels)

    def test_job_scam_detected(self, engine):
        result = engine.analyze(
            "Work from home! Easy data entry job. Earn Rs 5000 daily. "
            "No experience required. Pay registration fee of Rs 500."
        )
        labels = [r.label for r in result.reasons]
        assert any("Job" in label for label in labels)

    def test_courier_scam_detected(self, engine):
        result = engine.analyze(
            "Your package is held at customs. Pay delivery fee of Rs 200. "
            "Your parcel will be blocked if not paid."
        )
        labels = [r.label for r in result.reasons]
        assert any("Courier" in label or "Delivery" in label for label in labels)


class TestHeuristicScoreRange:
    def test_score_never_below_zero(self, engine):
        for text in ["", "hi", "ok", "yes"]:
            result = engine.analyze(text)
            assert result.score >= 0

    def test_score_never_above_100(self, engine):
        text = (
            "URGENT otp bank win lottery prize click bit.ly/abc download install "
            "verify account immediately bitcoin crypto send money trust us guaranteed "
            "arrest warrant income tax fir stranded hospital send money"
        )
        result = engine.analyze(text)
        assert result.score <= 100

    def test_reasons_not_empty_for_scam(self, engine):
        result = engine.analyze(
            "Click bit.ly/xyz now! Share OTP 123456. Win prize. Bank account suspended urgent."
        )
        assert len(result.reasons) > 0

    def test_category_assigned(self, engine):
        result = engine.analyze("Share your OTP to verify your bank account.")
        assert result.detected_category != ScamCategory.unknown or result.score < 20
