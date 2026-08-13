import json
import logging
from typing import Optional

import redis.asyncio as aioredis

from app.core.config import get_settings

logger = logging.getLogger(__name__)

# Lazy-initialised client — never crashes the API process if Redis is down at
# boot. Module-level ``redis_client`` (used by scan.py's SSE endpoint) is
# resolved through module __getattr__ so it is only created on first use.
_redis_client: Optional[aioredis.Redis] = None

# Sentinel used to remember a failed init attempt so we do not retry a known-
# broken configuration on every call.
_init_failed = False


def _get_redis() -> Optional[aioredis.Redis]:
    """Return a shared Redis client, creating it on first call.

    Returns None (and logs a warning once) if the configured Redis URL is
    unreachable or mis-configured, so the scan pipeline can continue without
    progress updates. Feature-unavailable is an explicit state, not an error.
    """
    global _redis_client, _init_failed
    if _redis_client is not None:
        return _redis_client
    if _init_failed:
        return None
    settings = get_settings()
    if settings.REDIS_URL.startswith("memory://"):
        _init_failed = True
        return None
    try:
        _redis_client = aioredis.from_url(settings.REDIS_URL, decode_responses=True)
        return _redis_client
    except Exception as exc:  # pragma: no cover - environment-specific
        _init_failed = True
        logger.warning(
            "Progress updates unavailable: Redis could not be initialised (%s). "
            "Scans will run without live progress; the SSE endpoint will report "
            "this explicitly.", exc,
        )
        return None


def __getattr__(name: str):
    """Resolve ``redis_client`` lazily on first attribute access."""
    if name == "redis_client":
        return _get_redis()
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


async def update_progress(scan_id: str, message: str, percentage: int) -> None:
    """Publish scan progress to Redis (best-effort — never raises).

    If Redis is unavailable the scan pipeline continues normally; the SSE
    endpoint will simply not receive real-time updates for this scan.
    """
    client = _get_redis()
    if client is None:
        logger.debug("Progress update skipped (Redis unavailable): %s %d%%", scan_id, percentage)
        return

    payload = json.dumps({
        "scan_id": scan_id,
        "message": message,
        "percentage": percentage,
    })
    try:
        await client.publish(f"scan_progress:{scan_id}", payload)
        # Cache the latest status so a client connecting after the publish still gets it.
        await client.setex(f"scan_status:{scan_id}", 3600, payload)
    except Exception as exc:
        logger.warning("Failed to publish progress for %s: %s", scan_id, exc)

