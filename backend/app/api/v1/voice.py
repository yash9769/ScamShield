"""
backend/app/api/v1/voice.py
POST /analyze-voice — audio transcription + scam analysis.
"""

from fastapi import APIRouter, File, Request, UploadFile, status
from fastapi.responses import JSONResponse

from app.core.config import get_settings
from app.core.exceptions import AudioProcessingError
from app.core.logging import get_logger
from app.middleware.rate_limit import limiter
from app.schemas.response import VoiceAnalysisResponse
from app.services.ai_engine import ai_engine
from app.services.voice_service import voice_service
from app.utils.file_utils import temp_audio_file, validate_audio_file

logger = get_logger(__name__)
router = APIRouter()
_settings = get_settings()


@router.post(
    "/analyze-voice",
    response_model=VoiceAnalysisResponse,
    summary="Analyse Voice/Audio for Scam",
    description=(
        "Accepts an audio file (mp3, wav, m4a, aac), transcribes it using "
        "OpenAI Whisper, then runs full scam analysis on the transcript. "
        "Maximum file size: 25 MB."
    ),
    tags=["Analysis"],
    responses={
        200: {"description": "Transcription + analysis result"},
        422: {"description": "Invalid audio file or no speech detected"},
        429: {"description": "Rate limit exceeded"},
        503: {"description": "Whisper service unavailable"},
    },
)
@limiter.limit(_settings.RATE_LIMIT_VOICE)
async def analyze_voice(
    request: Request,
    file: UploadFile = File(..., description="Audio file to transcribe and analyse"),
) -> VoiceAnalysisResponse:
    """
    Analyse audio content for scam signals.

    **Pipeline:**
    1. Validate format and file size
    2. Write to secure temp file
    3. Transcribe with Whisper (auto-detects language)
    4. Delete temp file
    5. Analyse transcript with full AI engine pipeline
    6. Return transcript + analysis
    """
    settings = get_settings()

    if not voice_service.available:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "error": "Voice Service Unavailable",
                "detail": "Whisper is not installed. Install with: pip install openai-whisper",
            },
        )

    # Read file bytes
    audio_bytes = await file.read()

    # Validate
    try:
        validate_audio_file(
            filename=file.filename or "audio.tmp",
            content_type=file.content_type or "",
            size_bytes=len(audio_bytes),
            max_bytes=settings.max_audio_bytes,
        )
    except ValueError as exc:
        raise AudioProcessingError(str(exc), filename=file.filename)

    logger.info(
        "Voice analysis request",
        extra={
            "filename": file.filename,
            "content_type": file.content_type,
            "size_bytes": len(audio_bytes),
        },
    )

    # Transcribe → analyse
    async with temp_audio_file(audio_bytes, file.filename or "audio.tmp") as audio_path:
        transcript = await voice_service.transcribe(audio_path)

    logger.info("Transcription complete", extra={"transcript_length": len(transcript)})

    analysis = await ai_engine.analyze(transcript)

    return VoiceAnalysisResponse(
        transcript=transcript,
        analysis=analysis,
    )
