"""
backend/app/schemas/request.py
Pydantic v2 request models for all ScamShield endpoints.
"""

from typing import List

from pydantic import BaseModel, Field, field_validator


class TextAnalysisRequest(BaseModel):
    """Request body for POST /analyze."""

    text: str = Field(
        ...,
        min_length=1,
        max_length=10_000,
        description="The message or text content to analyse for scam signals.",
        examples=["Congratulations! You have won Rs 10,00,000. Click here to claim."],
    )

    @field_validator("text")
    @classmethod
    def strip_and_validate(cls, v: str) -> str:
        """Strip surrounding whitespace and reject blank strings."""
        stripped = v.strip()
        if not stripped:
            raise ValueError("text must not be empty or whitespace-only")
        return stripped

    model_config = {
        "json_schema_extra": {
            "example": {
                "text": "Dear customer, your SBI account has been suspended. "
                        "Please verify your details at http://sbi-verify.xyz"
            }
        }
    }


class BatchAnalysisRequest(BaseModel):
    """Request body for POST /analyze-batch."""

    items: List[str] = Field(
        ...,
        min_length=1,
        max_length=20,
        description="List of text messages to analyse (max 20).",
    )

    @field_validator("items")
    @classmethod
    def validate_items(cls, v: List[str]) -> List[str]:
        """Strip items and remove empties."""
        cleaned = [item.strip() for item in v if item.strip()]
        if not cleaned:
            raise ValueError("items must contain at least one non-empty string")
        return cleaned

    model_config = {
        "json_schema_extra": {
            "example": {
                "items": [
                    "Your OTP is 123456. Never share it.",
                    "Hi, can we connect on LinkedIn?",
                    "You won a lottery! Claim at bit.ly/xyz",
                ]
            }
        }
    }
