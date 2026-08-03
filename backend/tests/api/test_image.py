"""
backend/tests/api/test_image.py
API tests for POST /analyze-image endpoint.
"""

from __future__ import annotations

import io

import pytest
from fastapi.testclient import TestClient


class TestImageEndpoint:
    def test_image_without_file_returns_422(self, client: TestClient):
        resp = client.post("/analyze-image")
        assert resp.status_code == 422

    def test_image_with_unsupported_format_returns_error(
        self, client: TestClient, minimal_wav_bytes: bytes
    ):
        """Uploading an audio file as image should fail."""
        resp = client.post(
            "/analyze-image",
            files={"file": ("audio.mp3", io.BytesIO(minimal_wav_bytes), "audio/mpeg")},
        )
        assert resp.status_code in (422, 503)

    def test_image_with_valid_png_returns_503_or_200(
        self, client: TestClient, minimal_png_bytes: bytes
    ):
        """
        In CI without EasyOCR installed, expect 503.
        In a full environment, expect 200 or 422 (no text found).
        """
        resp = client.post(
            "/analyze-image",
            files={"file": ("test.png", io.BytesIO(minimal_png_bytes), "image/png")},
        )
        assert resp.status_code in (200, 422, 503)

    def test_image_with_oversized_file_returns_error(self, client: TestClient):
        """Uploading a file exceeding 10MB should fail."""
        big_bytes = b"0" * (11 * 1024 * 1024)  # 11 MB
        resp = client.post(
            "/analyze-image",
            files={"file": ("big.jpg", io.BytesIO(big_bytes), "image/jpeg")},
        )
        assert resp.status_code in (422, 503)

    def test_image_503_response_schema(self, client: TestClient, minimal_png_bytes: bytes):
        """When EasyOCR is not installed, the 503 response should have error/detail."""
        resp = client.post(
            "/analyze-image",
            files={"file": ("test.png", io.BytesIO(minimal_png_bytes), "image/png")},
        )
        if resp.status_code == 503:
            data = resp.json()
            assert "error" in data
            assert "detail" in data

    def test_image_200_response_schema(self, client: TestClient, minimal_png_bytes: bytes):
        """When OCR succeeds, response should have extracted_text and analysis."""
        resp = client.post(
            "/analyze-image",
            files={"file": ("test.png", io.BytesIO(minimal_png_bytes), "image/png")},
        )
        if resp.status_code == 200:
            data = resp.json()
            assert "extracted_text" in data
            assert "analysis" in data
            assert "riskScore" in data["analysis"]
