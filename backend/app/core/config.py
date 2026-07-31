"""
backend/app/core/config.py
Application configuration loaded from environment variables.
"""

from __future__ import annotations

from functools import lru_cache
from typing import List

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Centralised application settings.

    All values can be overridden via environment variables or a .env file.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ── App ──────────────────────────────────────────────────────────────────
    APP_NAME: str = "ScamShield API"
    VERSION: str = "2.0.0"
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"

    # ── CORS ─────────────────────────────────────────────────────────────────
    ALLOWED_ORIGINS: List[str] = Field(
        default=["*"],
        description="List of allowed CORS origins",
    )

    # ── AI / Gemini ───────────────────────────────────────────────────────────
    GEMINI_API_KEY: str = Field(default="", description="Google Gemini API key")
    GEMINI_MODELS: List[str] = Field(
        default=["gemini-2.0-flash", "gemini-2.0-flash-lite"],
        description="Ordered list of Gemini models to try",
    )
    GEMINI_TIMEOUT: float = Field(default=15.0, description="Gemini request timeout in seconds")
    GEMINI_MAX_RETRIES: int = Field(default=2, description="Max retry attempts per model")
    GEMINI_TEMPERATURE: float = Field(default=0.1, description="Gemini generation temperature")

    # ── OSINT ─────────────────────────────────────────────────────────────────
    VIRUSTOTAL_API_KEY: str = Field(default="", description="VirusTotal API key")
    OSINT_TIMEOUT: float = Field(default=8.0, description="OSINT service timeout in seconds")
    OSINT_CACHE_TTL: int = Field(default=3600, description="OSINT cache TTL in seconds")

    # ── Redis ─────────────────────────────────────────────────────────────────
    REDIS_URL: str = Field(
        default="redis://localhost:6379",
        description="Redis connection URL. Use 'memory://' for in-memory fallback.",
    )

    # ── Rate Limiting ─────────────────────────────────────────────────────────
    RATE_LIMIT_ANALYZE: str = Field(default="60/minute", description="Rate limit for /analyze")
    RATE_LIMIT_VOICE: str = Field(default="10/minute", description="Rate limit for /analyze-voice")
    RATE_LIMIT_IMAGE: str = Field(default="10/minute", description="Rate limit for /analyze-image")
    RATE_LIMIT_BATCH: str = Field(default="20/minute", description="Rate limit for /analyze-batch")

    # ── Voice / Whisper ───────────────────────────────────────────────────────
    WHISPER_MODEL: str = Field(
        default="base",
        description="Whisper model size: tiny, base, small, medium, large",
    )
    MAX_AUDIO_SIZE_MB: int = Field(default=25, description="Max audio file size in MB")

    # ── OCR ───────────────────────────────────────────────────────────────────
    OCR_LANGUAGES: List[str] = Field(
        default=["en", "hi"],
        description="EasyOCR language codes",
    )
    MAX_IMAGE_SIZE_MB: int = Field(default=10, description="Max image file size in MB")
    OCR_GPU: bool = Field(default=False, description="Enable GPU for EasyOCR")

    # ── Batch ─────────────────────────────────────────────────────────────────
    BATCH_MAX_ITEMS: int = Field(default=20, description="Max items in a batch request")
    BATCH_CONCURRENCY: int = Field(default=5, description="Concurrent batch processing tasks")

    # ── Score Weights ─────────────────────────────────────────────────────────
    GEMINI_WEIGHT: float = Field(default=0.55, description="Weight for Gemini score")
    HEURISTIC_WEIGHT: float = Field(default=0.30, description="Weight for heuristic score")
    OSINT_WEIGHT: float = Field(default=0.15, description="Weight for OSINT score")

    @field_validator("LOG_LEVEL")
    @classmethod
    def validate_log_level(cls, v: str) -> str:
        """Ensure log level is a valid Python logging level."""
        valid = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}
        upper = v.upper()
        if upper not in valid:
            raise ValueError(f"LOG_LEVEL must be one of {valid}")
        return upper

    @field_validator("WHISPER_MODEL")
    @classmethod
    def validate_whisper_model(cls, v: str) -> str:
        """Ensure whisper model is valid."""
        valid = {"tiny", "base", "small", "medium", "large"}
        if v.lower() not in valid:
            raise ValueError(f"WHISPER_MODEL must be one of {valid}")
        return v.lower()

    @property
    def gemini_available(self) -> bool:
        """Check if Gemini is configured."""
        return bool(self.GEMINI_API_KEY)

    @property
    def virustotal_available(self) -> bool:
        """Check if VirusTotal is configured."""
        return bool(self.VIRUSTOTAL_API_KEY)

    @property
    def max_audio_bytes(self) -> int:
        """Max audio size in bytes."""
        return self.MAX_AUDIO_SIZE_MB * 1024 * 1024

    @property
    def max_image_bytes(self) -> int:
        """Max image size in bytes."""
        return self.MAX_IMAGE_SIZE_MB * 1024 * 1024


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return cached application settings."""
    return Settings()
