"""
backend/app/core/exceptions.py
Custom exception hierarchy for ScamShield.
"""

from __future__ import annotations


class ScamShieldError(Exception):
    """Base exception for all ScamShield errors."""

    def __init__(self, message: str, detail: str | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.detail = detail or message


class AnalysisError(ScamShieldError):
    """Raised when the analysis pipeline fails unrecoverably."""


class GeminiError(ScamShieldError):
    """Raised when Gemini returns an unexpected error."""


class GeminiQuotaError(GeminiError):
    """Raised when all Gemini quota is exhausted."""


class AudioProcessingError(ScamShieldError):
    """Raised when audio validation or transcription fails."""

    def __init__(self, message: str, filename: str | None = None) -> None:
        super().__init__(message)
        self.filename = filename


class OCRError(ScamShieldError):
    """Raised when image validation or OCR extraction fails."""

    def __init__(self, message: str, filename: str | None = None) -> None:
        super().__init__(message)
        self.filename = filename


class OsintTimeoutError(ScamShieldError):
    """Raised when an OSINT lookup exceeds the configured timeout."""

    def __init__(self, service: str) -> None:
        super().__init__(f"OSINT service '{service}' timed out")
        self.service = service


class RateLimitError(ScamShieldError):
    """Raised when the client exceeds the configured rate limit."""


class ValidationError(ScamShieldError):
    """Raised when request input fails business-rule validation."""
