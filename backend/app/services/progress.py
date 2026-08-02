import json
import logging
import redis.asyncio as redis
from app.core.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

redis_client = redis.from_url(settings.REDIS_URL, decode_responses=True)

async def update_progress(scan_id: str, message: str, percentage: int):
    """
    Publish progress updates to Redis so the SSE endpoint can stream it.
    """
    payload = json.dumps({
        "scan_id": scan_id,
        "message": message,
        "percentage": percentage
    })
    try:
        await redis_client.publish(f"scan_progress:{scan_id}", payload)
        # Also cache the latest progress in case the client connects late
        await redis_client.setex(f"scan_status:{scan_id}", 3600, payload)
    except Exception as e:
        logger.error(f"Failed to publish progress for {scan_id}: {e}")
