"""
backend/tests/conftest.py
Shared pytest fixtures for all ScamShield tests.

AUTH NOTE: the production default is API_AUTH_ENABLED=true. The broad suite
below runs with auth disabled (trusted-network mode) so engine/endpoint
behaviour can be tested without per-request tokens; the auth-on path is
explicitly covered by tests/api/test_auth.py.
"""

from __future__ import annotations

import io
import os
from typing import Generator
from unittest.mock import AsyncMock, MagicMock, patch

# Must be set before app.main is imported (settings are cached at import time).
os.environ["API_AUTH_ENABLED"] = "false"
os.environ["ENABLE_DOCS"] = "false"
os.environ["DEBUG"] = "false"
os.environ["ALLOWED_ORIGINS"] = "[]"

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models.enums import IconCategory, ScamCategory, ScamClassification, AnalysisSource, RecommendedAction
from app.schemas.response import AnalysisResult, DetectionReason


# ── Test client ───────────────────────────────────────────────────────────────

@pytest.fixture(scope="session")
def client() -> Generator[TestClient, None, None]:
    """HTTP test client for the FastAPI app."""
    with TestClient(app, raise_server_exceptions=False) as c:
        yield c


# ── Sample payloads ───────────────────────────────────────────────────────────

@pytest.fixture
def safe_text() -> str:
    return "Hi! Are you coming to the team meeting at 3pm today?"


@pytest.fixture
def scam_text() -> str:
    return (
        "URGENT! Your SBI bank account has been suspended. "
        "Verify your KYC immediately to avoid permanent closure. "
        "Click here: http://sbi-verify.xyz/kyc and share your OTP with our agent."
    )


@pytest.fixture
def lottery_text() -> str:
    return (
        "Congratulations! You have won Rs 10,00,000 in the Lucky Draw. "
        "You are the winner. Claim your prize within 24 hours. "
        "Call now: 9876543210. Do not ignore this final notice."
    )


@pytest.fixture
def crypto_text() -> str:
    return (
        "Double your Bitcoin in 48 hours! Invest in our guaranteed crypto scheme. "
        "Send USDT to wallet: 0xABC123. Risk free investment opportunity!"
    )


@pytest.fixture
def mock_analysis_result() -> AnalysisResult:
    """A pre-built AnalysisResult for mocking AI engine responses."""
    return AnalysisResult(
        classification=ScamClassification.scam,
        riskScore=85,
        reasons=[
            DetectionReason(
                label="Financial Keywords",
                description="Detected sensitive financial terms.",
                scoreContribution=30,
                iconCategory=IconCategory.financial,
            )
        ],
        summary="HIGH CONFIDENCE SCAM.",
        aiPowered=True,
        category=ScamCategory.bank_scam,
        confidence=90,
        recommended_action=RecommendedAction.block_and_report,
        source=AnalysisSource.hybrid,
    )


@pytest.fixture
def mock_safe_result() -> AnalysisResult:
    """A pre-built safe AnalysisResult."""
    return AnalysisResult(
        classification=ScamClassification.safe,
        riskScore=5,
        reasons=[
            DetectionReason(
                label="No Threats Detected",
                description="Message appears legitimate.",
                scoreContribution=0,
                iconCategory=IconCategory.safe,
            )
        ],
        summary="No suspicious patterns detected.",
        aiPowered=False,
        category=ScamCategory.safe,
        confidence=85,
        recommended_action=RecommendedAction.no_action,
        source=AnalysisSource.heuristic,
    )


# ── Audio fixture ─────────────────────────────────────────────────────────────

@pytest.fixture
def minimal_wav_bytes() -> bytes:
    """Minimal valid WAV file (44-byte header, 0 samples)."""
    import struct
    # WAV header: RIFF chunk + fmt chunk + data chunk (empty)
    data = struct.pack(
        "<4sI4s4sIHHIIHH4sI",
        b"RIFF", 36, b"WAVE",
        b"fmt ", 16,
        1,     # PCM
        1,     # 1 channel (mono)
        16000, # 16 kHz sample rate
        32000, # byte rate
        2,     # block align
        16,    # bits per sample
        b"data", 0,
    )
    return data


# ── Image fixture ─────────────────────────────────────────────────────────────

@pytest.fixture
def minimal_png_bytes() -> bytes:
    """Minimal valid 1x1 red PNG."""
    import base64
    # Pre-encoded 1x1 red PNG
    png_b64 = (
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI6QAAAABJRU5ErkJggg=="
    )
    return base64.b64decode(png_b64)
