"""
backend/app/api/v1/health.py
GET /health — service status, uptime, and downstream connectivity check.
"""

import asyncio
import importlib.util
import os
import shutil
import time

from fastapi import APIRouter, Request

from app.core.config import get_settings
from app.core.logging import get_logger
from app.schemas.response import HealthResponse

logger = get_logger(__name__)

router = APIRouter()

# Track app start time for uptime calculation
_START_TIME = time.monotonic()


async def _check_redis(redis_url: str) -> dict:
    """Ping Redis and return its availability status."""
    if redis_url.startswith("memory://"):
        return {"available": True, "type": "in-memory"}

    try:
        import redis.asyncio as aioredis  # type: ignore

        client = aioredis.from_url(redis_url, socket_connect_timeout=2)
        await asyncio.wait_for(client.ping(), timeout=2.0)
        await client.aclose()
        return {"available": True, "url": redis_url.split("@")[-1]}
    except Exception as exc:
        return {"available": False, "error": str(exc)[:100]}


def _apk_tool_status() -> dict:
    jadx_ok = shutil.which("jadx") is not None
    apktool_ok = shutil.which("apktool") is not None
    yara_ok = importlib.util.find_spec("yara") is not None
    andro_ok = importlib.util.find_spec("androguard") is not None
    return {
        "jadx": {"available": jadx_ok},
        "apktool": {"available": apktool_ok},
        "yara": {"available": yara_ok},
        "androguard": {"available": andro_ok},
        "mobsf": {
            "available": bool(os.getenv("MOBSF_API_KEY")) and bool(os.getenv("MOBSF_URL")),
            "configured": bool(os.getenv("MOBSF_API_KEY")),
        },
        "full_pipeline": all([jadx_ok, apktool_ok, yara_ok, andro_ok]),
    }


def _check_whisper_installed() -> bool:
    """Check if Whisper is installed WITHOUT loading the model (fast)."""
    return importlib.util.find_spec("whisper") is not None


def _check_ocr_installed() -> bool:
    """Check if EasyOCR is installed WITHOUT loading the model (fast)."""
    return importlib.util.find_spec("easyocr") is not None


@router.get(
    "/health",
    response_model=HealthResponse,
    summary="Health Check",
    tags=["System"],
)
async def health_check(request: Request) -> dict:
    """
    Return service status, uptime, and downstream service availability.

    ``status`` is ``"healthy"`` when the API is serving, ``"degraded"`` when
    a non-critical downstream (LLM, OCR, voice) is unavailable. This endpoint
    is intentionally public (no client auth) so load balancers and Docker
    healthchecks can probe it without a device token.

    Note: OCR and Voice availability is reported based on package installation
    only — models are NOT loaded during health checks to keep response times fast.
    """
    settings = get_settings()

    gemini_available = settings.gemini_available
    groq_available = settings.groq_available
    llm_available = gemini_available or groq_available
    # Lightweight package presence checks — do NOT call service.available
    # which triggers lazy model loading (takes 4-15 seconds first time).
    whisper_available = _check_whisper_installed()
    ocr_available = _check_ocr_installed()
    virustotal_available = settings.virustotal_available
    safe_browsing_available = bool(settings.GOOGLE_SAFE_BROWSING_API_KEY)
    abuseipdb_available = bool(settings.ABUSEIPDB_API_KEY)
    redis_status = await _check_redis(settings.REDIS_URL)

    api_status = {
        "gemini": {"available": gemini_available},
        "groq": {"available": groq_available},
        "llm": {"available": llm_available},
        "virustotal": {"available": virustotal_available},
        "safe_browsing": {"available": safe_browsing_available},
        "abuseipdb": {"available": abuseipdb_available},
        "whisper": {"available": whisper_available},
        "easyocr": {"available": ocr_available},
        "redis": redis_status,
        "apk_tools": _apk_tool_status(),
    }

    # Downstream failures degrade (but never take down) the API.
    status = "healthy" if (llm_available or whisper_available or ocr_available) else "degraded"

    return {
        "status": status,
        "version": settings.VERSION,
        "uptime_seconds": round(time.monotonic() - _START_TIME, 2),
        "api_status": api_status,
    }
