"""
backend/tests/integration/test_full_pipeline.py
Integration tests for the complete analysis pipeline.
Tests end-to-end flow without mocking internal services.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


class TestFullPipeline:
    """Tests that run the full heuristic pipeline (no external APIs required)."""

    def test_scam_message_pipeline(self, client: TestClient, scam_text: str):
        """Full pipeline should classify a clear scam message."""
        resp = client.post("/analyze", json={"text": scam_text})
        assert resp.status_code == 200
        data = resp.json()
        # Heuristic should catch this
        assert data["riskScore"] >= 30
        assert data["classification"] in ("suspicious", "scam")
        assert len(data["reasons"]) > 0
        assert data["summary"]

    def test_safe_message_pipeline(self, client: TestClient, safe_text: str):
        """Full pipeline should leave benign messages as safe."""
        resp = client.post("/analyze", json={"text": safe_text})
        assert resp.status_code == 200
        data = resp.json()
        assert data["classification"] in ("safe", "suspicious")
        assert data["riskScore"] <= 40

    def test_batch_full_pipeline(self, client: TestClient, scam_text: str, safe_text: str):
        """Batch endpoint processes mixed items correctly."""
        resp = client.post(
            "/analyze-batch",
            json={"items": [scam_text, safe_text, "Win a lottery prize now!"]}
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] == 3
        assert data["processed"] == 3
        assert data["failed"] == 0

        # Scam text (index 0) should score higher than safe text (index 1)
        results_by_index = {r["index"]: r["result"] for r in data["results"]}
        scam_score = results_by_index[0]["riskScore"]
        safe_score = results_by_index[1]["riskScore"]
        assert scam_score >= safe_score

    def test_health_check_pipeline(self, client: TestClient):
        """Health check should always return a valid response."""
        resp = client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] in ("healthy", "degraded")
        assert data["uptime_seconds"] > 0

    def test_consecutive_requests(self, client: TestClient):
        """Multiple sequential requests should all succeed."""
        texts = [
            "Your OTP is 123456, please share it with the agent",
            "Hey, want to grab lunch tomorrow?",
            "You have won 5 lakh in the lottery! Claim now bit.ly/claim",
            "Meeting at 3pm in conference room 2.",
        ]
        for text in texts:
            resp = client.post("/analyze", json={"text": text})
            assert resp.status_code == 200
            data = resp.json()
            assert 0 <= data["riskScore"] <= 100

    def test_response_time_header_present(self, client: TestClient, safe_text: str):
        """All responses should include the X-Response-Time header."""
        resp = client.post("/analyze", json={"text": safe_text})
        assert "x-response-time" in resp.headers or "X-Response-Time" in resp.headers

    def test_request_id_header_present(self, client: TestClient, safe_text: str):
        """All responses should include the X-Request-ID header."""
        resp = client.post("/analyze", json={"text": safe_text})
        headers_lower = {k.lower(): v for k, v in resp.headers.items()}
        assert "x-request-id" in headers_lower

    def test_cors_headers_on_options(self, client: TestClient):
        """CORS preflight from a NON-allowed origin is rejected.

        ALLOWED_ORIGINS defaults to an empty list (never "*") so a browser
        preflight from an unknown origin must NOT be granted CORS access — the
        security-correct outcome is 400. Only origins explicitly configured in
        ALLOWED_ORIGINS receive access-control headers.
        """
        resp = client.options(
            "/analyze",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "POST",
            }
        )
        assert resp.status_code == 400

    def test_unknown_route_returns_404(self, client: TestClient):
        """Unknown routes should return 404."""
        resp = client.get("/nonexistent-route")
        assert resp.status_code == 404
