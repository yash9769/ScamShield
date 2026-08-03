"""
backend/tests/api/test_analyze.py
API tests for POST /analyze endpoint.
"""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient


class TestAnalyzeEndpoint:
    def test_analyze_returns_200(self, client: TestClient, safe_text: str):
        resp = client.post("/analyze", json={"text": safe_text})
        assert resp.status_code == 200

    def test_analyze_response_schema(self, client: TestClient, safe_text: str):
        resp = client.post("/analyze", json={"text": safe_text})
        data = resp.json()
        assert "classification" in data
        assert "riskScore" in data
        assert "reasons" in data
        assert "summary" in data
        assert "aiPowered" in data

    def test_analyze_classification_is_valid(self, client: TestClient, scam_text: str):
        resp = client.post("/analyze", json={"text": scam_text})
        data = resp.json()
        assert data["classification"] in ("safe", "suspicious", "scam")

    def test_analyze_risk_score_in_range(self, client: TestClient, scam_text: str):
        resp = client.post("/analyze", json={"text": scam_text})
        data = resp.json()
        assert 0 <= data["riskScore"] <= 100

    def test_analyze_reasons_is_list(self, client: TestClient, scam_text: str):
        resp = client.post("/analyze", json={"text": scam_text})
        data = resp.json()
        assert isinstance(data["reasons"], list)
        assert len(data["reasons"]) > 0

    def test_analyze_reason_has_required_fields(self, client: TestClient, scam_text: str):
        resp = client.post("/analyze", json={"text": scam_text})
        data = resp.json()
        for reason in data["reasons"]:
            assert "label" in reason
            assert "description" in reason
            assert "scoreContribution" in reason
            assert "iconCategory" in reason

    def test_analyze_empty_text_422(self, client: TestClient):
        resp = client.post("/analyze", json={"text": ""})
        assert resp.status_code == 422

    def test_analyze_whitespace_only_422(self, client: TestClient):
        resp = client.post("/analyze", json={"text": "   "})
        assert resp.status_code == 422

    def test_analyze_text_too_long_422(self, client: TestClient):
        resp = client.post("/analyze", json={"text": "a" * 10_001})
        assert resp.status_code == 422

    def test_analyze_missing_text_field_422(self, client: TestClient):
        resp = client.post("/analyze", json={})
        assert resp.status_code == 422

    def test_analyze_scam_message_high_score(self, client: TestClient, scam_text: str):
        resp = client.post("/analyze", json={"text": scam_text})
        data = resp.json()
        # Heuristic should catch the obvious scam signals
        assert data["riskScore"] >= 30

    def test_analyze_safe_message_low_score(self, client: TestClient, safe_text: str):
        resp = client.post("/analyze", json={"text": safe_text})
        data = resp.json()
        assert data["riskScore"] <= 40

    def test_analyze_has_v2_extended_fields(self, client: TestClient, safe_text: str):
        """V2 fields should be present but don't break Flutter (additive)."""
        resp = client.post("/analyze", json={"text": safe_text})
        data = resp.json()
        assert "category" in data
        assert "confidence" in data
        assert "recommended_action" in data

    def test_analyze_icon_category_is_valid(self, client: TestClient, scam_text: str):
        valid_icons = {"financial", "link", "urgency", "suspicious", "manipulation",
                       "safe", "government", "romance", "crypto", "job"}
        resp = client.post("/analyze", json={"text": scam_text})
        data = resp.json()
        for reason in data["reasons"]:
            assert reason["iconCategory"] in valid_icons

    def test_analyze_no_text_key_422(self, client: TestClient):
        resp = client.post("/analyze", json={"message": "hello"})
        assert resp.status_code == 422

    def test_analyze_lottery_message(self, client: TestClient, lottery_text: str):
        resp = client.post("/analyze", json={"text": lottery_text})
        data = resp.json()
        assert data["classification"] in ("suspicious", "scam")

    def test_analyze_crypto_scam(self, client: TestClient, crypto_text: str):
        resp = client.post("/analyze", json={"text": crypto_text})
        data = resp.json()
        assert data["riskScore"] >= 30
