"""
backend/tests/api/test_batch.py
API tests for POST /analyze-batch endpoint.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


class TestBatchEndpoint:
    def test_batch_returns_200(self, client: TestClient):
        resp = client.post(
            "/analyze-batch",
            json={"items": ["Hello, how are you?", "Share your OTP now!"]}
        )
        assert resp.status_code == 200

    def test_batch_response_schema(self, client: TestClient):
        resp = client.post(
            "/analyze-batch",
            json={"items": ["test message one", "test message two"]}
        )
        data = resp.json()
        assert "results" in data
        assert "processed" in data
        assert "failed" in data
        assert "total" in data

    def test_batch_total_matches_input(self, client: TestClient):
        items = ["msg1", "msg2", "msg3"]
        resp = client.post("/analyze-batch", json={"items": items})
        data = resp.json()
        assert data["total"] == len(items)

    def test_batch_results_count_matches_total(self, client: TestClient):
        items = ["msg1", "msg2", "msg3"]
        resp = client.post("/analyze-batch", json={"items": items})
        data = resp.json()
        assert len(data["results"]) == len(items)

    def test_batch_each_result_has_schema(self, client: TestClient):
        resp = client.post(
            "/analyze-batch",
            json={"items": ["Your OTP is 123456. Share it now.", "Hey are you free?"]}
        )
        data = resp.json()
        for item in data["results"]:
            assert "index" in item
            assert "text_preview" in item
            assert "success" in item

    def test_batch_result_has_analysis(self, client: TestClient):
        resp = client.post(
            "/analyze-batch",
            json={"items": ["Your account is suspended. Verify KYC immediately."]}
        )
        data = resp.json()
        result = data["results"][0]
        assert result["success"] is True
        assert result["result"] is not None
        assert "riskScore" in result["result"]

    def test_batch_empty_items_422(self, client: TestClient):
        resp = client.post("/analyze-batch", json={"items": []})
        assert resp.status_code == 422

    def test_batch_too_many_items_422(self, client: TestClient):
        resp = client.post("/analyze-batch", json={"items": ["msg"] * 21})
        assert resp.status_code == 422

    def test_batch_missing_items_422(self, client: TestClient):
        resp = client.post("/analyze-batch", json={})
        assert resp.status_code == 422

    def test_batch_all_whitespace_items_422(self, client: TestClient):
        resp = client.post("/analyze-batch", json={"items": ["   ", "  "]})
        assert resp.status_code == 422

    def test_batch_mixed_safe_and_scam(self, client: TestClient):
        resp = client.post(
            "/analyze-batch",
            json={
                "items": [
                    "Hi, are you coming to the meeting?",
                    "URGENT! Your bank account suspended. Share OTP now!",
                ]
            }
        )
        data = resp.json()
        assert data["total"] == 2
        assert data["processed"] == 2

    def test_batch_single_item(self, client: TestClient):
        resp = client.post("/analyze-batch", json={"items": ["single message"]})
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] == 1

    def test_batch_results_ordered_by_index(self, client: TestClient):
        items = [f"message number {i}" for i in range(5)]
        resp = client.post("/analyze-batch", json={"items": items})
        data = resp.json()
        indices = [r["index"] for r in data["results"]]
        assert indices == sorted(indices)
