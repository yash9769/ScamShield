"""
backend/app/api/v1/breach.py
GET /breach — Email breach/exposure analysis endpoint using XposedOrNot.
"""

from fastapi import APIRouter, Depends, Request, Query

from app.core.config import get_settings
from app.core.logging import get_logger
from app.middleware.rate_limit import limiter
from app.schemas.response import BreachResponse
from app.services.xposedornot import XposedOrNotService

logger = get_logger(__name__)
router = APIRouter()
settings = get_settings()
xposedornot_service = XposedOrNotService()

@router.get(
    "/breach",
    response_model=BreachResponse,
    summary="Check Email for Data Breaches",
    description=(
        "Checks a given email address for data breaches / exposure using the public "
        "XposedOrNot API. Returns a normalized representation of all exposures found."
    ),
    tags=["Analysis"],
    responses={
        200: {"description": "Breach lookup result"},
        400: {"description": "Invalid email address format"},
        429: {"description": "Rate limit exceeded"},
        502: {"description": "Error communicating with breach database"},
        504: {"description": "Breach database request timed out"},
    },
)
@limiter.limit(settings.RATE_LIMIT_BREACH)
async def check_email_breach(
    request: Request,
    email: str = Query(..., description="Email address to scan"),
) -> BreachResponse:
    """
    Check if the specified email address has been compromised in any public data leaks.
    """
    logger.info(
        "Email breach lookup request",
        extra={"email": email},
    )

    result = await xposedornot_service.check_email_exposure(email)

    logger.info(
        "Email breach lookup response",
        extra={
            "email": email,
            "exposed": result["exposed"],
            "breach_count": result["breachCount"],
        },
    )

    return BreachResponse(**result)
