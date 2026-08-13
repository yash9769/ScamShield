"""
backend/app/schemas/response.py
Pydantic v2 response models — fully backward-compatible with Flutter frontend.
"""

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from app.models.enums import (
    AnalysisSource,
    IconCategory,
    RecommendedAction,
    ScamCategory,
    ScamClassification,
)


class DetectionReason(BaseModel):
    """A single detection signal with its contribution to the risk score."""

    label: str = Field(..., description="Short label (max 5 words)")
    description: str = Field(..., description="Detailed explanation of the finding")
    scoreContribution: int = Field(..., ge=0, le=40, description="Points contributed to risk score")
    iconCategory: IconCategory = Field(..., description="UI icon category")

    model_config = {"use_enum_values": True}


class OsintDetail(BaseModel):
    """OSINT enrichment details attached to the analysis."""

    urls_found: List[str] = Field(default_factory=list)
    malicious_urls: List[str] = Field(default_factory=list)
    whois_domain_age_days: Optional[int] = None
    whois_registrar: Optional[str] = None
    virustotal_checked: bool = False
    osint_score: int = Field(default=0, ge=0, le=100)


class AnalysisResult(BaseModel):
    """
    Primary analysis response — backward-compatible with Flutter api_service.dart.

    Flutter reads: classification, riskScore, reasons, summary, aiPowered.
    New fields (category, confidence, recommended_action, source, osint) are
    additive and ignored by the existing Flutter client.
    """

    # ── Flutter-compatible core fields ────────────────────────────────────────
    classification: ScamClassification = Field(..., description="safe | suspicious | scam")
    riskScore: int = Field(..., ge=0, le=100, description="Overall risk score 0-100")
    reasons: List[DetectionReason] = Field(..., description="List of detection reasons")
    summary: str = Field(..., description="1-2 sentence plain-English verdict")
    aiPowered: bool = Field(default=True, description="True if Gemini contributed to analysis")
    # Analysis status — distinguishes "analyzed" from "unavailable / failed".
    # A client MUST never render a non-analyzed result as a green "safe"
    # verdict. Legacy clients that ignore this field still get the old shape.
    analysisStatus: str = Field(
        default="analyzed",
        description="analyzed | partial | unavailable | failed",
    )

    # ── Extended fields (new in v2) ───────────────────────────────────────────
    category: ScamCategory = Field(
        default=ScamCategory.unknown,
        description="Detailed scam category",
    )
    confidence: int = Field(
        default=50,
        ge=0,
        le=100,
        description="Confidence in the classification 0-100",
    )
    recommended_action: RecommendedAction = Field(
        default=RecommendedAction.be_cautious,
        description="Recommended user action",
    )
    source: AnalysisSource = Field(
        default=AnalysisSource.heuristic,
        description="Which engine produced the result",
    )
    osint: Optional[OsintDetail] = Field(
        default=None,
        description="OSINT enrichment data (if available)",
    )

    model_config = {"use_enum_values": True}


class BatchItemResult(BaseModel):
    """Result for a single item in a batch request."""

    index: int = Field(..., description="Zero-based index of the item in the input list")
    text_preview: str = Field(..., description="First 80 chars of the analysed text")
    result: Optional[AnalysisResult] = None
    error: Optional[str] = None
    success: bool = True


class BatchAnalysisResponse(BaseModel):
    """Response for POST /analyze-batch."""

    results: List[BatchItemResult]
    processed: int = Field(..., description="Number of items successfully processed")
    failed: int = Field(..., description="Number of items that failed")
    total: int = Field(..., description="Total items submitted")


class VoiceAnalysisResponse(BaseModel):
    """Response for POST /analyze-voice."""

    transcript: str = Field(..., description="Whisper transcript of the audio")
    analysis: AnalysisResult
    audio_duration_seconds: Optional[float] = None


class ImageAnalysisResponse(BaseModel):
    """Response for POST /analyze-image."""

    extracted_text: str = Field(..., description="OCR-extracted text from the image")
    analysis: AnalysisResult
    ocr_confidence: Optional[float] = None


class HealthResponse(BaseModel):
    """Response for GET /health."""

    status: str = Field(..., description="'healthy' or 'degraded'")
    version: str
    uptime_seconds: float
    api_status: Dict[str, Any] = Field(
        default_factory=dict,
        description="Status of each downstream service",
    )


class ErrorResponse(BaseModel):
    """Standard error envelope returned by the global exception handler."""

    error: str
    detail: str
    request_id: Optional[str] = None


class Breach(BaseModel):
    name: str = Field(..., description="Name of the breach")
    domain: str = Field(..., description="Domain of the breached site")
    date: str = Field(..., description="Date of the breach (YYYY-MM-DD or year)")
    dataClasses: List[str] = Field(..., description="List of exposed data types")


class BreachResponse(BaseModel):
    email: str = Field(..., description="The queried email address")
    exposed: bool = Field(..., description="True if any exposures were found")
    breachCount: int = Field(..., description="Total number of breaches found")
    breaches: List[Breach] = Field(..., description="List of breaches")
    source: str = Field(default="XposedOrNot", description="Data source")
    checkedAt: str = Field(..., description="Timestamp when checked")

