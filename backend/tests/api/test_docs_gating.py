"""
backend/tests/api/test_docs_gating.py
Verifies that /docs, /redoc and /openapi.json are only exposed when
ENABLE_DOCS=true or DEBUG=true, and are 404 in the production default.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


class TestDocsDisabledByDefault:
    """Production default: docs and OpenAPI are turned OFF."""

    @pytest.mark.parametrize("path", ["/docs", "/redoc", "/openapi.json"])
    def test_docs_paths_return_404(self, client: TestClient, path: str):
        resp = client.get(path)
        assert resp.status_code == 404


class TestDocsFactoryGating:
    def _build(self, monkeypatch, **overrides):
        from app.core.config import Settings
        import app.main

        patched = Settings(**overrides)
        monkeypatch.setattr(app.main, "settings", patched)
        return app.main.create_app()

    def test_enabled_when_flag_set(self, monkeypatch):
        test_app = self._build(monkeypatch, ENABLE_DOCS=True, DEBUG=False)
        assert test_app.docs_url == "/docs"
        assert test_app.redoc_url == "/redoc"
        assert test_app.openapi_url == "/openapi.json"

    def test_enabled_in_debug_mode(self, monkeypatch):
        test_app = self._build(monkeypatch, ENABLE_DOCS=False, DEBUG=True)
        assert test_app.docs_url == "/docs"
        assert test_app.openapi_url == "/openapi.json"

    def test_disabled_when_both_unset(self, monkeypatch):
        test_app = self._build(monkeypatch, ENABLE_DOCS=False, DEBUG=False)
        assert test_app.docs_url is None
        assert test_app.redoc_url is None
        assert test_app.openapi_url is None
