"""
backend/app/api/v1/analyze.py
POST /analyze — primary text scam analysis endpoint.
Backward-compatible with the Flutter frontend.
"""

from fastapi import APIRouter, Depends, Request

from app.core.config import get_settings
from app.core.logging import get_logger
from app.middleware.rate_limit import limiter
from app.schemas.request import TextAnalysisRequest
from app.schemas.response import AnalysisResult
from app.services.ai_engine import ai_engine

logger = get_logger(__name__)
router = APIRouter()
settings = get_settings()


@router.post(
    "/analyze",
    response_model=AnalysisResult,
    summary="Analyse Text for Scam",
    description=(
        "Analyses a text message for scam signals using Gemini AI (primary) "
        "with automatic heuristic fallback. Always returns a result. "
        "**Fully backward-compatible with the Flutter frontend.**"
    ),
    tags=["Analysis"],
    responses={
        200: {"description": "Analysis result"},
        422: {"description": "Invalid or empty input"},
        429: {"description": "Rate limit exceeded"},
    },
)
@limiter.limit(settings.RATE_LIMIT_ANALYZE)
async def analyze_text(
    request: Request,
    body: TextAnalysisRequest,
) -> AnalysisResult:
    """
    Analyse text content for scam indicators.

    **Workflow:**
    1. Sanitise and validate input
    2. Run Gemini AI analysis (with automatic retry)
    3. Run heuristic analysis in parallel
    4. Run OSINT checks (VirusTotal, WHOIS) in parallel
    5. Aggregate scores with weighted formula
    6. Return unified result

    If Gemini is unavailable, gracefully falls back to heuristic-only mode.
    """
    logger.info(
        "Text analysis request",
        extra={"text_length": len(body.text), "preview": body.text[:50]},
    )

    result = await ai_engine.analyze(body.text)

    logger.info(
        "Text analysis response",
        extra={
            "classification": result.classification,
            "risk_score": result.riskScore,
            "ai_powered": result.aiPowered,
        },
    )

    return result
