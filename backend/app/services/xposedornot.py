import logging
import httpx
import re
from datetime import datetime, timezone
from typing import Dict, Any, List
from fastapi import HTTPException

from app.core.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

EMAIL_REGEX = re.compile(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")

class XposedOrNotService:
    def __init__(self) -> None:
        self.api_key = settings.XPOSEDORNOT_API_KEY
        self.timeout = settings.OSINT_TIMEOUT  # Default timeout from settings

    def validate_email(self, email: str) -> bool:
        """Validate email format client/server-side using regex."""
        return bool(EMAIL_REGEX.match(email.strip()))

    async def check_email_exposure(self, email: str) -> Dict[str, Any]:
        """
        Accepts an email address, validates/sanitizes, queries XposedOrNot,
        and parses the response into our normalized internal format.
        
        Note: XposedOrNot API key is optional but recommended for better accuracy.
        Requests without a key may still work but are rate-limited more aggressively.
        """
        clean_email = email.strip().lower()
        if not self.validate_email(clean_email):
            logger.warning("Invalid email format requested", extra={"email": clean_email})
            raise HTTPException(status_code=400, detail="Invalid email format.")

        # Log warning if API key is not configured
        if not self.api_key:
            logger.warning(
                "XposedOrNot API key not configured - breach check will have limited accuracy",
                extra={"email": clean_email}
            )

        # XposedOrNot breach-analytics endpoint
        url = f"https://api.xposedornot.com/v1/breach-analytics?email={clean_email}"
        headers = {}
        if self.api_key:
            headers["x-api-key"] = self.api_key

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            try:
                response = await client.get(url, headers=headers)
            except httpx.TimeoutException as exc:
                logger.error("XposedOrNot API request timed out", extra={"error": str(exc)})
                raise HTTPException(status_code=504, detail="Breach database request timed out.")
            except httpx.RequestError as exc:
                logger.error("XposedOrNot API request failed", extra={"error": str(exc)})
                raise HTTPException(status_code=503, detail="Breach database service unavailable.")

            if response.status_code == 401:
                logger.error("XposedOrNot API authentication failed - invalid or missing API key")
                raise HTTPException(
                    status_code=502,
                    detail="Breach database authentication failed. API key may be missing or invalid."
                )

            if response.status_code == 429:
                logger.warning(
                    "XposedOrNot API rate limited (429)",
                    extra={"has_api_key": bool(self.api_key)}
                )
                raise HTTPException(
                    status_code=429,
                    detail="Too many requests. Please try again later."
                )

            if response.status_code == 404:
                # Typically returned for invalid email format or if not found (we treat as safe)
                return {
                    "email": clean_email,
                    "exposed": False,
                    "breachCount": 0,
                    "breaches": [],
                    "source": "XposedOrNot",
                    "checkedAt": datetime.now(timezone.utc).isoformat()
                }

            if response.status_code != 200:
                logger.error(
                    "XposedOrNot API returned unexpected status code",
                    extra={
                        "status_code": response.status_code,
                        "has_api_key": bool(self.api_key)
                    }
                )
                raise HTTPException(status_code=502, detail="Error communicating with breach database.")

            try:
                data = response.json()
            except ValueError as exc:
                logger.error("Failed to parse XposedOrNot API response JSON", extra={"error": str(exc)})
                raise HTTPException(status_code=502, detail="Malformed response from breach database.")

            # Parse and normalize response
            exposed_breaches = data.get("ExposedBreaches")
            if not exposed_breaches or not isinstance(exposed_breaches, dict):
                return {
                    "email": clean_email,
                    "exposed": False,
                    "breachCount": 0,
                    "breaches": [],
                    "source": "XposedOrNot",
                    "checkedAt": datetime.now(timezone.utc).isoformat()
                }

            breach_details = exposed_breaches.get("breaches_details", [])
            if not isinstance(breach_details, list):
                breach_details = []

            normalized_breaches = []
            for b in breach_details:
                if not isinstance(b, dict):
                    continue

                # Clean and parse date
                raw_date = b.get("xposed_date", "unknown")
                if len(raw_date) == 4 and raw_date.isdigit():
                    formatted_date = f"{raw_date}-01-01"
                else:
                    formatted_date = raw_date

                # Split and clean data classes
                data_classes_str = b.get("xposed_data", "")
                data_classes = [d.strip() for d in data_classes_str.split(";") if d.strip()]

                normalized_breaches.append({
                    "name": b.get("breach") or "Unknown Breach",
                    "domain": b.get("domain") or "unknown.com",
                    "date": formatted_date,
                    "dataClasses": data_classes
                })

            return {
                "email": clean_email,
                "exposed": len(normalized_breaches) > 0,
                "breachCount": len(normalized_breaches),
                "breaches": normalized_breaches,
                "source": "XposedOrNot",
                "checkedAt": datetime.now(timezone.utc).isoformat()
            }
