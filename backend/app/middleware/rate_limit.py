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
    """Extract the real client IP for rate limiting.

    ``X-Forwarded-For`` is only trusted when the request's direct peer is a
    configured trusted proxy (TRUSTED_PROXIES). Otherwise we use the direct
    peer address, so a remote attacker cannot spoof or rotate
    ``X-Forwarded-For`` to bypass the limiter.
    """
    peer = get_remote_address(request)
    settings = get_settings()
    trusted = set(settings.TRUSTED_PROXIES)
    if trusted and peer in trusted:
        forwarded_for = request.headers.get("X-Forwarded-For")
        if forwarded_for:
            # Proxies APPEND the peer's real address to the header, so the
            # right-most entry is the one added by our trusted proxy. The
            # left-most entry is client-supplied and spoofable.
            entries = [e.strip() for e in forwarded_for.split(",") if e.strip()]
            if entries:
                return entries[-1]
    return peer


def create_limiter() -> Limiter:
    """Create a SlowAPI Limiter instance with fallback to in-memory storage."""
    settings = get_settings()

    storage_uri = settings.REDIS_URL
    if storage_uri.startswith("memory://"):
        # Deliberate configuration — silent, not an error or a fallback.
        storage_uri = "memory://"
    elif storage_uri.startswith("redis://"):
        # A single best-effort ping at boot decides between Redis-backed and
        # in-memory limiting. When Redis is missing, the limiter degrades to
        # per-process memory with one clear line — the health endpoint reports
        # the same state so operators are not surprised.
        try:
            import redis
            r = redis.Redis.from_url(storage_uri, socket_connect_timeout=0.3)
            r.ping()
        except Exception:
            logger.info(
                "Rate limiter: Redis unreachable at %s — falling back to "
                "in-memory per-process limits (stateless across instances).",
                storage_uri.split("@")[-1],
            )
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
