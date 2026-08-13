"""
backend/tests/unit/test_health_capabilities.py
Unit tests for extended /health endpoint capabilities exposure.
"""

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_capabilities_exposure():
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()

    assert "status" in data
    assert "version" in data
    assert "uptime_seconds" in data
    assert "api_status" in data

    api_status = data["api_status"]
    assert "gemini" in api_status
    assert "groq" in api_status
    assert "llm" in api_status
    assert "virustotal" in api_status
    assert "safe_browsing" in api_status
    assert "abuseipdb" in api_status
    assert "whisper" in api_status
    assert "easyocr" in api_status
    assert "apk_tools" in api_status
    apk_tools = api_status["apk_tools"]
    for tool in ("jadx", "apktool", "yara", "androguard", "mobsf", "full_pipeline"):
        assert tool in apk_tools, f"missing apk_tools.{tool} in /health"
    assert isinstance(apk_tools["full_pipeline"], bool)
    if apk_tools["full_pipeline"]:
        # full_pipeline is the conjunction of all on-box tools being present.
        assert apk_tools["jadx"]["available"] is True
        assert apk_tools["apktool"]["available"] is True
