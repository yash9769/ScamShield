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
from app.services.gemini_service import gemini_service
from app.services.ocr_service import ocr_service
from app.services.voice_service import voice_service

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
    """Report which APK-analysis tools are actually present on this host.

    The on-box pipeline (JADX, APKTool, YARA, Androguard) is optional: a
    deployment without the tools still serves text/voice/image analysis and
    falls back to heuristic-only APK handling. This endpoint makes that state
    explicit so operators (and the client) never assume a full pipeline that
    is not installed.
    """
    return {
        "jadx": {"available": shutil.which("jadx") is not None},
        "apktool": {"available": shutil.which("apktool") is not None},
        "yara": {"available": importlib.util.find_spec("yara") is not None},
        "androguard": {"available": importlib.util.find_spec("androguard") is not None},
        "mobsf": {
            "available": bool(os.getenv("MOBSF_API_KEY")) and bool(os.getenv("MOBSF_URL")),
            "configured": bool(os.getenv("MOBSF_API_KEY")),
        },
        "full_pipeline": all(
            [
                shutil.which("jadx") is not None,
                shutil.which("apktool") is not None,
                importlib.util.find_spec("yara") is not None,
                importlib.util.find_spec("androguard") is not None,
            ]
        ),
    }


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
    """
    settings = get_settings()

    gemini_available = settings.gemini_available
    groq_available = settings.groq_available
    llm_available = gemini_available or groq_available
    whisper_available = bool(voice_service.available)
    ocr_available = bool(ocr_service.available)
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
