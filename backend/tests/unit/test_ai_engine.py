"""
backend/tests/unit/test_ai_engine.py
Unit tests for the AI engine score aggregation logic.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.models.enums import AnalysisSource, ScamClassification, RecommendedAction
from app.schemas.response import OsintDetail
from app.services.ai_engine import AIEngine, _score_to_classification, _score_to_recommended_action


class TestScoreToClassification:
    def test_score_0_is_safe(self):
        assert _score_to_classification(0) == ScamClassification.safe

    def test_score_30_is_safe(self):
        assert _score_to_classification(30) == ScamClassification.safe

    def test_score_31_is_suspicious(self):
        assert _score_to_classification(31) == ScamClassification.suspicious

    def test_score_65_is_suspicious(self):
        assert _score_to_classification(65) == ScamClassification.suspicious

    def test_score_66_is_scam(self):
        assert _score_to_classification(66) == ScamClassification.scam

    def test_score_100_is_scam(self):
        assert _score_to_classification(100) == ScamClassification.scam


class TestRecommendedAction:
    def test_score_0_no_action(self):
        action = _score_to_recommended_action(0, ScamClassification.safe)
        assert action == RecommendedAction.no_action

    def test_score_50_be_cautious(self):
        action = _score_to_recommended_action(50, ScamClassification.suspicious)
        assert action == RecommendedAction.be_cautious

    def test_score_70_do_not_respond(self):
        action = _score_to_recommended_action(70, ScamClassification.scam)
        assert action == RecommendedAction.do_not_respond

    def test_score_85_block_and_report(self):
        action = _score_to_recommended_action(85, ScamClassification.scam)
        assert action == RecommendedAction.block_and_report


class TestAIEngineWithMocks:
    @pytest.mark.asyncio
    async def test_heuristic_fallback_when_gemini_unavailable(self):
        """When Gemini returns None, heuristic engine should produce a result."""
        engine = AIEngine()

        with patch("app.services.ai_engine.gemini_service") as mock_gemini, \
             patch("app.services.ai_engine.osint_service") as mock_osint:

            mock_gemini.analyze = AsyncMock(return_value=None)
            mock_osint.analyze = AsyncMock(return_value=MagicMock(
                score=0,
                detail=OsintDetail(urls_found=[], malicious_urls=[], osint_score=0)
            ))

            result = await engine.analyze(
                "URGENT! Share your OTP to avoid bank account suspension."
            )

        assert result is not None
        assert result.riskScore >= 0
        assert result.aiPowered is False
        assert result.source == AnalysisSource.heuristic.value

    @pytest.mark.asyncio
    async def test_gemini_result_used_when_available(self, mock_analysis_result):
        """When Gemini returns a result, it should be the primary signal."""
        engine = AIEngine()

        with patch("app.services.ai_engine.gemini_service") as mock_gemini, \
             patch("app.services.ai_engine.osint_service") as mock_osint:

            mock_gemini.analyze = AsyncMock(return_value=mock_analysis_result)
            mock_osint.analyze = AsyncMock(return_value=MagicMock(
                score=0,
                detail=OsintDetail(urls_found=[], malicious_urls=[], osint_score=0)
            ))

            result = await engine.analyze("Your account is compromised. Send OTP.")

        assert result is not None
        assert result.aiPowered is True

    @pytest.mark.asyncio
    async def test_malicious_url_overrides_classification(self):
        """OSINT malicious URL detection should force scam classification."""
        engine = AIEngine()

        safe_result = MagicMock()
        safe_result.riskScore = 10
        safe_result.reasons = []
        safe_result.summary = "Looks safe"
        safe_result.category = "Safe"
        safe_result.confidence = 80
        safe_result.recommended_action = "No action required. Message appears safe."
        safe_result.source = "gemini"

        osint_with_malicious = MagicMock()
        osint_with_malicious.score = 80
        osint_with_malicious.detail = OsintDetail(
            urls_found=["http://evil.com"],
            malicious_urls=["http://evil.com"],
            osint_score=80,
            virustotal_checked=True,
        )

        with patch("app.services.ai_engine.gemini_service") as mock_gemini, \
             patch("app.services.ai_engine.osint_service") as mock_osint:

            mock_gemini.analyze = AsyncMock(return_value=safe_result)
            mock_osint.analyze = AsyncMock(return_value=osint_with_malicious)

            result = await engine.analyze("Check out this link: http://evil.com")

        assert result.classification == ScamClassification.scam.value or result.riskScore >= 66

    @pytest.mark.asyncio
    async def test_result_score_clamped_to_100(self):
        """Final score should never exceed 100."""
        engine = AIEngine()

        with patch("app.services.ai_engine.gemini_service") as mg, \
             patch("app.services.ai_engine.osint_service") as mo:
            mg.analyze = AsyncMock(return_value=None)
            mo.analyze = AsyncMock(return_value=MagicMock(
                score=100,
                detail=OsintDetail(urls_found=[], malicious_urls=[], osint_score=100)
            ))

            result = await engine.analyze(
                "URGENT otp bank win lottery prize click bit.ly/abc download "
                "install verify account immediately bitcoin crypto"
            )

        assert result.riskScore <= 100
        assert result.riskScore >= 0
