"""
backend/app/api/v1/batch.py
POST /analyze-batch — parallel analysis of multiple text messages.
"""

import asyncio
from typing import List

from fastapi import APIRouter, Request

from app.core.config import get_settings
from app.core.logging import get_logger
from app.middleware.rate_limit import limiter
from app.schemas.request import BatchAnalysisRequest
from app.schemas.response import BatchAnalysisResponse, BatchItemResult
from app.services.ai_engine import ai_engine
from app.utils.text_utils import truncate

logger = get_logger(__name__)
router = APIRouter()
_settings = get_settings()


async def _analyze_one(index: int, text: str) -> BatchItemResult:
    """Analyse a single batch item, capturing any errors gracefully."""
    preview = truncate(text, max_chars=80)
    try:
        result = await ai_engine.analyze(text)
        return BatchItemResult(
            index=index,
            text_preview=preview,
            result=result,
            success=True,
        )
    except Exception as exc:
        logger.warning(
            "Batch item failed",
            extra={"index": index, "error": str(exc)[:200]},
        )
        return BatchItemResult(
            index=index,
            text_preview=preview,
            result=None,
            error=str(exc)[:200],
            success=False,
        )


@router.post(
    "/analyze-batch",
    response_model=BatchAnalysisResponse,
    summary="Batch Analyse Multiple Texts",
    description=(
        "Accepts a list of text messages (max 20) and analyses each one in parallel "
        "using the full AI engine pipeline. Returns results for every item, "
        "including any that failed individually."
    ),
    tags=["Analysis"],
    responses={
        200: {"description": "Batch analysis results"},
        422: {"description": "Empty or oversized batch"},
        429: {"description": "Rate limit exceeded"},
    },
)
@limiter.limit(_settings.RATE_LIMIT_BATCH)
async def analyze_batch(
    request: Request,
    body: BatchAnalysisRequest,
) -> BatchAnalysisResponse:
    """
    Analyse multiple messages in parallel.

    **Features:**
    - Processes up to 20 items per request
    - Concurrency limited to 5 simultaneous AI calls (configurable)
    - Each item failure is isolated — one failure doesn't cancel others
    - Returns per-item success/error status
    """
    settings = get_settings()
    items = body.items
    total = len(items)

    logger.info("Batch analysis request", extra={"total_items": total})

    # Use semaphore to limit concurrent AI calls
    semaphore = asyncio.Semaphore(settings.BATCH_CONCURRENCY)

    async def _limited_analyze(index: int, text: str) -> BatchItemResult:
        async with semaphore:
            return await _analyze_one(index, text)

    tasks = [_limited_analyze(i, text) for i, text in enumerate(items)]
    results: List[BatchItemResult] = await asyncio.gather(*tasks)

    # Sort by original index to maintain order
    results.sort(key=lambda r: r.index)

    processed = sum(1 for r in results if r.success)
    failed = total - processed

    logger.info(
        "Batch analysis complete",
        extra={"total": total, "processed": processed, "failed": failed},
    )

    return BatchAnalysisResponse(
        results=results,
        processed=processed,
        failed=failed,
        total=total,
    )
