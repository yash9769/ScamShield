"""
backend/app/api/v1/analyze.py
POST /analyze — primary text scam analysis endpoint.
Backward-compatible with the Flutter frontend.
"""

import hashlib

from fastapi import APIRouter, Depends, Request

from app.core.config import get_settings
from app.core.logging import get_logger
from app.middleware.api_auth import get_api_client
from app.middleware.rate_limit import limiter
from app.schemas.request import TextAnalysisRequest
from app.schemas.response import AnalysisResult
from app.services.ai_engine import ai_engine
from app.services.audit import log_audit_event

logger = get_logger(__name__)
router = APIRouter()


def _input_fingerprint(text: str) -> str:
    """Non-reversible fingerprint of analysed content for logs/audit."""
    return hashlib.sha256(text.encode("utf-8", "replace")).hexdigest()[:16]


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
@limiter.limit("60/minute")
async def analyze_text(
    request: Request,
    body: TextAnalysisRequest,
    client: str | None = Depends(get_api_client),
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
        extra={
            "text_length": len(body.text),
            "text_sha256_prefix": _input_fingerprint(body.text),
            "client_fingerprint": client,
        },
    )

    result = await ai_engine.analyze(body.text)

    log_audit_event(
        event_type="analyze",
        target="",  # raw content is never stored — see log_audit_event
        target_fingerprint=_input_fingerprint(body.text),
        target_length=len(body.text),
        risk_score=result.riskScore,
        risk_level=str(result.classification),
    )

    logger.info(
        "Text analysis response",
        extra={
            "classification": result.classification,
            "risk_score": result.riskScore,
            "ai_powered": result.aiPowered,
        },
    )

    return result
