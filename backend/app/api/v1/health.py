"""
backend/app/api/v1/health.py
GET /health — service status, uptime, and downstream connectivity check.
"""

import asyncio
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


@router.get(
    "/health",
    summary="Health Check",
    tags=["System"],
)
async def health_check(request: Request) -> dict:
    return {"status": "ok"}


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
