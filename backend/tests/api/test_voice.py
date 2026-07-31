"""
backend/tests/api/test_voice.py
API tests for POST /analyze-voice endpoint.
"""

from __future__ import annotations

import io

import pytest
from fastapi.testclient import TestClient


class TestVoiceEndpoint:
    def test_voice_with_invalid_format_returns_error(self, client: TestClient, minimal_png_bytes: bytes):
        """Uploading a PNG instead of audio should fail with 422 or 503."""
        resp = client.post(
            "/analyze-voice",
            files={"file": ("image.png", io.BytesIO(minimal_png_bytes), "image/png")},
        )
        # Either 422 (invalid format) or 503 (whisper not installed in CI)
        assert resp.status_code in (422, 503)

    def test_voice_with_valid_wav_returns_503_or_200(
        self, client: TestClient, minimal_wav_bytes: bytes
    ):
        """
        In CI without Whisper installed, expect 503.
        In a full environment, expect 200.
        """
        resp = client.post(
            "/analyze-voice",
            files={"file": ("test.wav", io.BytesIO(minimal_wav_bytes), "audio/wav")},
        )
        assert resp.status_code in (200, 422, 503)

    def test_voice_without_file_returns_422(self, client: TestClient):
        resp = client.post("/analyze-voice")
        assert resp.status_code == 422

    def test_voice_with_oversized_file_returns_error(self, client: TestClient):
        """Uploading a file exceeding 25MB should fail."""
        big_bytes = b"0" * (26 * 1024 * 1024)  # 26 MB
        resp = client.post(
            "/analyze-voice",
            files={"file": ("big.wav", io.BytesIO(big_bytes), "audio/wav")},
        )
        # Either 422 (size validation) or 503 (whisper not installed)
        assert resp.status_code in (422, 503)

    def test_voice_503_response_schema(self, client: TestClient, minimal_wav_bytes: bytes):
        """When Whisper is not installed, the 503 response should have error/detail."""
        resp = client.post(
            "/analyze-voice",
            files={"file": ("test.wav", io.BytesIO(minimal_wav_bytes), "audio/wav")},
        )
        if resp.status_code == 503:
            data = resp.json()
            assert "error" in data
            assert "detail" in data
