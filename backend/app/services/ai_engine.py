"""
backend/app/services/ai_engine.py
Orchestrates Gemini + Heuristic + OSINT into a single analysis result.
This is the central brain of ScamShield.
"""

from __future__ import annotations

import asyncio

from app.core.config import get_settings
from app.core.logging import get_logger
from app.models.enums import (
    AnalysisSource,
    RecommendedAction,
    ScamCategory,
    ScamClassification,
)
from app.schemas.response import AnalysisResult, DetectionReason
from app.services.gemini_service import gemini_service
from app.services.heuristic_service import HeuristicService
from app.services.osint_service import osint_service
from app.utils.text_utils import sanitize_text

logger = get_logger(__name__)

_heuristic = HeuristicService()


def _score_to_classification(score: float) -> ScamClassification:
    if score >= 66:
        return ScamClassification.scam
    if score >= 31:
        return ScamClassification.suspicious
    return ScamClassification.safe


def _score_to_recommended_action(score: float, classification: ScamClassification) -> RecommendedAction:
    if score >= 80:
        return RecommendedAction.block_and_report
    if score >= 66:
        return RecommendedAction.do_not_respond
    if score >= 31:
        return RecommendedAction.be_cautious
    return RecommendedAction.no_action


def _score_to_confidence(gemini_available: bool, heuristic_score: int) -> int:
    """Estimate confidence based on signal richness."""
    if gemini_available:
        return min(95, 70 + (heuristic_score // 5))
    # Heuristic-only confidence
    if heuristic_score >= 60:
        return 75
    if heuristic_score >= 30:
        return 60
    return 80  # High confidence in "safe" when score is 0


class AIEngine:
    """
    Central orchestration engine for ScamShield analysis.

    Score formula:
        final = (gemini * 0.55) + (heuristic * 0.30) + (osint * 0.15)

    When Gemini is unavailable, weights shift:
        final = (heuristic * 0.80) + (osint * 0.20)
    """

    def __init__(self) -> None:
        self._settings = get_settings()

    async def analyze(self, text: str) -> AnalysisResult:
        """
        Run the full analysis pipeline and return a consolidated AnalysisResult.

        Always returns a result — never raises.
        """
        clean_text = sanitize_text(text)

        # ── Run Gemini and OSINT concurrently, heuristic is sync ──────────────
        gemini_task = asyncio.create_task(gemini_service.analyze(clean_text))
        osint_task = asyncio.create_task(osint_service.analyze(clean_text))

        heuristic_result = _heuristic.analyze(clean_text)

        gemini_result = await gemini_task
        osint_result = await osint_task

        # ── Aggregate scores ──────────────────────────────────────────────────
        heuristic_score = float(heuristic_result.score)
        osint_score = float(osint_result.score)

        if gemini_result is not None:
            gemini_score = float(gemini_result.riskScore)
            gw = self._settings.GEMINI_WEIGHT
            hw = self._settings.HEURISTIC_WEIGHT
            ow = self._settings.OSINT_WEIGHT
            final_score = (gemini_score * gw) + (heuristic_score * hw) + (osint_score * ow)
            source = AnalysisSource.hybrid if heuristic_score > 0 else AnalysisSource.gemini
        else:
            # Gemini unavailable — redistribute weights
            final_score = (heuristic_score * 0.80) + (osint_score * 0.20)
            source = AnalysisSource.heuristic

        final_score = max(0.0, min(100.0, final_score))
        final_score_int = round(final_score)

        classification = _score_to_classification(final_score)
        recommended_action = _score_to_recommended_action(final_score, classification)
        confidence = _score_to_confidence(gemini_result is not None, int(heuristic_score))

        # ── Merge reasons (Gemini primary, heuristic supplements) ─────────────
        if gemini_result is not None:
            reasons = gemini_result.reasons
            category = gemini_result.category
            summary = gemini_result.summary
            # Append unique heuristic reasons not already covered
            gemini_labels = {r.label.lower() for r in reasons}
            for hr in heuristic_result.reasons:
                if hr.label.lower() not in gemini_labels and hr.scoreContribution > 0:
                    reasons.append(hr)
            ai_powered = True
        else:
            reasons = heuristic_result.reasons
            category = heuristic_result.detected_category
            summary = _build_heuristic_summary(classification, final_score_int)
            ai_powered = False

        # ── Override classification with aggregated score ──────────────────────
        # (Gemini may have said "safe" but OSINT found malicious URLs)
        if osint_result.detail.malicious_urls:
            classification = ScamClassification.scam
            final_score_int = max(final_score_int, 75)
            reasons.append(DetectionReason(
                label="Malicious URL (VirusTotal)",
                description=f"VirusTotal flagged {len(osint_result.detail.malicious_urls)} URL(s) "
                            "as malicious. Do NOT click any links in this message.",
                scoreContribution=30,
                iconCategory="link",
            ))

        # ── Log summary ───────────────────────────────────────────────────────
        logger.info(
            "Analysis complete",
            extra={
                "source": source.value,
                "final_score": final_score_int,
                "classification": classification.value,
                "category": category if isinstance(category, str) else category.value,
                "gemini_score": gemini_result.riskScore if gemini_result else None,
                "heuristic_score": int(heuristic_score),
                "osint_score": int(osint_score),
            },
        )

        return AnalysisResult(
            classification=classification,
            riskScore=final_score_int,
            reasons=reasons[:10],  # Cap at 10 reasons for readability
            summary=summary,
            aiPowered=ai_powered,
            category=category,
            confidence=confidence,
            recommended_action=recommended_action,
            source=source,
            osint=osint_result.detail if osint_result.score > 0 or osint_result.detail.urls_found else None,
        )


def _build_heuristic_summary(classification: ScamClassification, score: int) -> str:
    """Build a plain-English summary when only the heuristic engine ran."""
    if classification == ScamClassification.safe:
        return "No suspicious patterns detected. This message appears to be safe."
    if classification == ScamClassification.suspicious:
        return (
            "Multiple warning signals detected. Do NOT share personal or financial "
            "information. Verify the sender independently before responding."
        )
    return (
        f"HIGH CONFIDENCE SCAM (score: {score}/100). This message uses classic social "
        "engineering tactics. Do not click any links, call any numbers, or share any data."
    )


# Module-level singleton
ai_engine = AIEngine()
