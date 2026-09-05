"""
backend/app/middleware/rate_limit.py
Rate limiting middleware using slowapi with graceful in-memory fallback.
"""

from __future__ import annotations

from fastapi import FastAPI, Request
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger(__name__)


def _get_client_ip(request: Request) -> str:
    """Extract real client IP.

    X-Forwarded-For is only trusted when TRUST_PROXY_HEADERS is enabled — it's a
    client-supplied header, and trusting it unconditionally lets any caller spoof
    a fresh IP on every request to bypass rate limits.
    """
    if get_settings().TRUST_PROXY_HEADERS:
        forwarded_for = request.headers.get("X-Forwarded-For")
        if forwarded_for:
            return forwarded_for.split(",")[0].strip()
    return get_remote_address(request)


def create_limiter() -> Limiter:
    """Create a SlowAPI Limiter instance with fallback to in-memory storage."""
    settings = get_settings()

    storage_uri = settings.REDIS_URL
    if not storage_uri or storage_uri.startswith("memory://") or storage_uri.startswith("redis://localhost"):
        # Test connection to redis quickly if it's localhost, or default to memory
        if storage_uri.startswith("redis://"):
            try:
                import redis
                r = redis.Redis.from_url(storage_uri, socket_connect_timeout=0.5)
                r.ping()
            except Exception:
                logger.info("Redis not reachable at %s, using in-memory rate limiting", storage_uri)
                storage_uri = "memory://"
        else:
            storage_uri = "memory://"

    try:
        limiter = Limiter(
            key_func=_get_client_ip,
            storage_uri=storage_uri,
        )
        logger.info("Rate limiter initialised", extra={"storage": storage_uri})
        return limiter
    except Exception as exc:
        logger.warning(
            "Rate limiter failed to connect to storage, using in-memory",
            extra={"error": str(exc)},
        )
        return Limiter(key_func=_get_client_ip, storage_uri="memory://")


def register_rate_limiter(app: FastAPI, limiter: Limiter) -> None:
    """Attach the limiter and its exception handler to the FastAPI app."""
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)


# Module-level singleton
limiter = create_limiter()
