"""
backend/tests/unit/test_heuristic_regressions.py
Messages the no-Gemini pipeline used to get wrong: scams rated "safe"
(electricity disconnection, SIM deactivation, lottery and job fees, a caller
asking for "the code") and a genuine bank OTP rated "suspicious". Checked
end to end through AIEngine, since that is what the API returns.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest

from app.services.ai_engine import AIEngine
from app.services.heuristic_service import asks_for_otp, keyword_hits
from app.services.osint_service import OsintScore

SCAMS = [
    "Congratulations! You won Rs 25,00,000 in KBC lottery. Pay Rs 5000 processing fee to claim.",
    "Dear customer your electricity will be disconnected tonight. Call 9876543210 immediately and pay Rs 10 via the link",
    "Your SIM will be deactivated within 24 hours due to incomplete KYC. Call 7003123456 now.",
    "Earn Rs 5000 daily working from home! Guaranteed returns, just pay Rs 500 registration fee to start.",
    "Hi this is the bank executive, please tell me the code you just received to stop the fraud transaction.",
]

GENUINE = [
    "Your OTP for HDFC netbanking login is 551203. Do not share it with anyone. Valid for 5 minutes.",
    "123456 is your WhatsApp code. Never share this code.",
    "Your electricity bill of Rs 1,240 for October is generated. Due date 5 Nov. Pay via the official app.",
    "Your shipping label is ready. Pickup tomorrow between 10am and 2pm.",
]


async def _classify(text: str) -> str:
    with patch("app.services.ai_engine.gemini_service.analyze", new=AsyncMock(return_value=None)), \
         patch("app.services.ai_engine.osint_service.analyze", new=AsyncMock(return_value=OsintScore())):
        result = await AIEngine().analyze(text)
    return getattr(result.classification, "value", result.classification)


@pytest.mark.parametrize("text", SCAMS)
async def test_scams_are_not_rated_safe(text):
    assert await _classify(text) != "safe"


@pytest.mark.parametrize("text", GENUINE)
async def test_genuine_messages_are_safe(text):
    assert await _classify(text) == "safe"


def test_otp_request_vs_delivery():
    assert asks_for_otp("Share OTP 482913 with our agent")
    assert not asks_for_otp("Your OTP is 551203. Do not share it with anyone.")
    assert not asks_for_otp("123456 is your WhatsApp code. Never share this code.")


def test_keywords_match_whole_words_only():
    assert keyword_hits({"pin", "win"}, "your shipping window") == []
    assert keyword_hits({"pin"}, "enter your pin now") == ["pin"]
