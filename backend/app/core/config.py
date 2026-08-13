"""
backend/app/core/config.py
Application configuration loaded from environment variables.
"""

from __future__ import annotations

import os
import sys
from functools import lru_cache
from typing import List

from pydantic import Field, field_validator, model_validator
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
    VERSION: str = "2.1.0"
    DEBUG: bool = False
    LOG_LEVEL: str = "INFO"

    # ── Interactive API docs / OpenAPI ───────────────────────────────────────
    # /docs, /redoc and /openapi.json expose the full route surface (including
    # admin endpoints) and are disabled by default in production. Enable them
    # explicitly for local development: ENABLE_DOCS=true or DEBUG=true.
    ENABLE_DOCS: bool = False

    # ── Admin / Operational security ─────────────────────────────────────────
    # There is intentionally NO default value. The process fails to start when
    # ADMIN_API_KEY is missing outside of CI/local-tests, so a misconfigured
    # deployment can never run with a guessable key.
    ADMIN_API_KEY: str = Field(
        default="",
        description="Required admin API key (Authorization: Bearer / X-Admin-Key)",
    )

    # ── Client authentication (device tokens / server keys) ─────────────────
    # Secure by default: client auth is ON unless deliberately disabled for a
    # self-hosted / trusted-network deployment. When enabled, protected
    # endpoints require either an X-Device-Token (a per-install anonymous token
    # generated on the client, never a hardcoded secret) or an X-API-Key from
    # API_KEYS.
    API_AUTH_ENABLED: bool = Field(
        default=True,
        description="Enforce device-token / API-key auth on all client endpoints",
    )
    API_KEYS: List[str] = Field(
        default_factory=list,
        description="Server-to-server API keys accepted in X-API-Key",
    )

    # ── Trusted reverse proxies ─────────────────────────────────────────────
    # Comma-separated list of proxy IPs/CIDRs that may set X-Forwarded-For.
    # When a request does NOT come from one of these, the rate limiter uses the
    # direct peer IP so a remote attacker cannot spoof/rotate X-Forwarded-For.
    TRUSTED_PROXIES: List[str] = Field(
        default_factory=list,
        description="Proxy addresses allowed to set X-Forwarded-For",
    )

    @field_validator("TRUSTED_PROXIES", mode="before")
    @classmethod
    def parse_proxy_list(cls, v):
        """Accept either a JSON list or a comma-separated env string."""
        if isinstance(v, str):
            return [item.strip() for item in v.split(",") if item.strip()]
        return v

    # ── CORS ─────────────────────────────────────────────────────────────────
    # Explicit origins only — never a wildcard. The mobile app does not use
    # browser CORS at all, so an empty list is the safe default.
    ALLOWED_ORIGINS: List[str] = Field(
        default_factory=list,
        description="Explicit list of allowed CORS origins",
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

    @property
    def gemini_available(self) -> bool:
        """Return True if Gemini API key is configured and non-empty."""
        return self.GEMINI_API_KEY.strip() != ""

    # ── AI / Groq ─────────────────────────────────────────────────────────────
    GROQ_API_KEY: str = Field(default="", description="Groq API key")
    GROQ_MODELS: List[str] = Field(
        default=["llama-3.3-70b-versatile", "llama-3.1-70b-versatile", "llama-3.1-8b-instant"],
        description="Ordered list of Groq models to try",
    )

    @property
    def groq_available(self) -> bool:
        """Return True if Groq API key is configured and non-empty."""
        return self.GROQ_API_KEY.strip() != ""

    # ── Database ──────────────────────────────────────────────────────────────
    DATABASE_URL: str = Field(
        default="postgresql+asyncpg://scamshield@localhost:5432/scamshield",
        description="PostgreSQL Database URL",
    )

    # ── OSINT ─────────────────────────────────────────────────────────────────
    VIRUSTOTAL_API_KEY: str = Field(default="", description="VirusTotal API key")
    GOOGLE_SAFE_BROWSING_API_KEY: str = Field(default="", description="Google Safe Browsing API key")
    ABUSEIPDB_API_KEY: str = Field(default="", description="AbuseIPDB API key")
    XPOSEDORNOT_API_KEY: str = Field(default="", description="XposedOrNot API key")
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
    RATE_LIMIT_BREACH: str = Field(default="30/minute", description="Rate limit for /breach")

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

    # ── LLM verdict cache ────────────────────────────────────────────────────
    # Caches the full AI-engine verdict keyed on a SHA-256 of the sanitised
    # text, cutting Gemini/Groq cost and latency for repeated messages.
    LLM_CACHE_TTL: int = Field(default=3600, description="LLM verdict cache TTL in seconds")
    LLM_CACHE_SIZE: int = Field(default=512, description="Max entries in the LLM verdict cache")

    # ── Risk weights ─────────────────────────────────────────────────────────
    RISK_WEIGHTS_PATH: str = Field(
        default="",
        description="Path to risk_weights.yaml (auto-detected when empty)",
    )

    # ── Audit log ────────────────────────────────────────────────────────────
    AUDIT_DB_PATH: str = Field(
        default="",
        description="SQLite path for the admin audit log (auto default when empty)",
    )

    # ── Crash reporting ──────────────────────────────────────────────────────
    SENTRY_DSN: str = Field(default="", description="Sentry DSN for server crash reporting")

    # ── Storage paths ────────────────────────────────────────────────────────
    # Docker deploys default these to /app/...; a local run resolves relative
    # to the backend/ working directory so it works without a mounted volume.
    UPLOAD_DIR: str = Field(default="uploads", description="APK upload directory")
    REPORTS_DIR: str = Field(default="reports", description="Scan report output directory")
    YARA_RULES_DIR: str = Field(default="", description="YARA rules directory (auto-detected when empty)")

    @field_validator("DEBUG", mode="before")
    @classmethod
    def tolerant_debug_flag(cls, v):
        """Coerce DEBUG so an unrelated env var cannot crash startup.

        Some build tools and shells export DEBUG=release / DEBUG=0 with a
        completely unrelated meaning. Only a positive value enables debug
        mode; anything unrecognised is treated as False instead of raising.
        """
        if isinstance(v, bool):
            return v
        if isinstance(v, str):
            lowered = v.strip().lower()
            if lowered in {"true", "1", "yes", "on", "debug"}:
                return True
        return False

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

    @model_validator(mode="after")
    def require_admin_key_outside_testing(self) -> "Settings":
        """Fail closed when ADMIN_API_KEY is missing in a production context.

        Local test runs (pytest, CI) receive a throwaway random key so the
        suite still boots; every real deployment MUST set ADMIN_API_KEY or the
        process refuses to start.
        """
        if self.ADMIN_API_KEY:
            return self

        testing = (
            "pytest" in sys.modules
            or os.getenv("PYTEST_CURRENT_TEST") is not None
            or os.getenv("CI") is not None
        )
        if not testing:
            raise ValueError(
                "ADMIN_API_KEY environment variable is required and must not be empty. "
                "Refusing to start with a missing or guessable admin key."
            )

        import secrets as _secrets

        self.ADMIN_API_KEY = _secrets.token_urlsafe(32)
        return self

    @model_validator(mode="after")
    def validate_production_api_keys(self) -> "Settings":
        """Warn about missing AI and OSINT API keys in production.
        
        AI services (Gemini, Groq) are critical for scam detection.
        OSINT services (VirusTotal, XposedOrNot) are optional but enhance analysis.
        """
        is_production = not self.DEBUG and os.getenv("CI") is None
        
        if is_production:
            missing_ai_keys = []
            if not self.GEMINI_API_KEY.strip():
                missing_ai_keys.append("GEMINI_API_KEY")
            if not self.GROQ_API_KEY.strip():
                missing_ai_keys.append("GROQ_API_KEY")
                
            if missing_ai_keys:
                # Log warning but don't fail — the app can fall back to heuristic scoring
                import logging
                logger = logging.getLogger(__name__)
                logger.warning(
                    f"Production deployment missing AI API keys: {', '.join(missing_ai_keys)}. "
                    f"Scam detection will fall back to heuristic scoring (lower accuracy). "
                    f"Set GEMINI_API_KEY and/or GROQ_API_KEY in environment."
                )
            
            # Optionally warn about missing OSINT keys (less critical)
            missing_osint = []
            if not self.VIRUSTOTAL_API_KEY.strip():
                missing_osint.append("VIRUSTOTAL_API_KEY")
            if not self.XPOSEDORNOT_API_KEY.strip():
                missing_osint.append("XPOSEDORNOT_API_KEY")
            
            if missing_osint:
                import logging
                logger = logging.getLogger(__name__)
                logger.debug(
                    f"Production deployment missing optional OSINT keys: {', '.join(missing_osint)}. "
                    f"Threat intelligence enrichment will be limited."
                )
        
        return self

    @model_validator(mode="after")
    def resolve_derived_paths(self) -> "Settings":
        """Fill in sensible defaults for audit DB / risk weights when unset."""
        if not self.AUDIT_DB_PATH:
            self.AUDIT_DB_PATH = os.path.join(os.getcwd(), "scamshield_audit.db")
        if not self.YARA_RULES_DIR:
            self.YARA_RULES_DIR = os.path.join(os.getcwd(), "yara_rules")
        if not self.RISK_WEIGHTS_PATH:
            # Support both local development and Docker mount path /app/app/config/risk_weights.yaml
            package_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            self.RISK_WEIGHTS_PATH = os.path.join(package_dir, "config", "risk_weights.yaml")
        return self

    @property
    def gemini_available(self) -> bool:
        """Check if Gemini is configured."""
        return bool(self.GEMINI_API_KEY) and not self.GEMINI_API_KEY.startswith("gsk_")

    @property
    def groq_available(self) -> bool:
        """Check if Groq is configured."""
        return bool(self.GROQ_API_KEY) or self.GEMINI_API_KEY.startswith("gsk_")

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