"""
backend/tests/unit/test_rate_limit_bypass.py
Unit tests for the client IP rate limiter resolution logic.
Ensures attackers cannot bypass rate limits by spoofing the X-Forwarded-For header
unless the request comes from a configured trusted proxy.
"""
from __future__ import annotations

import pytest
from fastapi import Request
from slowapi.util import get_remote_address

from app.core.config import get_settings
from app.middleware.rate_limit import _get_client_ip

class MockRequest:
    def __init__(self, client_host: str, headers: dict[str, str]):
        self.client = type("Client", (), {"host": client_host})()
        self.headers = headers

def test_client_ip_no_trusted_proxies(monkeypatch):
    """When TRUSTED_PROXIES is empty, X-Forwarded-For must be completely ignored."""
    settings = get_settings()
    monkeypatch.setattr(settings, "TRUSTED_PROXIES", [])

    # Peer is 192.168.1.100, attempts to spoof with X-Forwarded-For
    req = MockRequest(
        client_host="192.168.1.100",
        headers={"X-Forwarded-For": "8.8.8.8, 1.1.1.1"}
    )
    # SlowAPI's default resolver (get_remote_address) uses request.client.host
    # We patch it or mock it. Since slowapi's key_func matches, let's verify:
    ip = _get_client_ip(req)
    assert ip == "192.168.1.100"

def test_client_ip_with_trusted_proxy_matching(monkeypatch):
    """When direct peer is a trusted proxy, extract the right-most address from X-Forwarded-For."""
    settings = get_settings()
    monkeypatch.setattr(settings, "TRUSTED_PROXIES", ["10.0.0.1"])

    # Request comes from trusted proxy 10.0.0.1
    req = MockRequest(
        client_host="10.0.0.1",
        headers={"X-Forwarded-For": "192.168.1.50, 1.1.1.1"}
    )
    ip = _get_client_ip(req)
    assert ip == "1.1.1.1"

def test_client_ip_with_trusted_proxy_not_matching(monkeypatch):
    """When direct peer is NOT a trusted proxy, ignore X-Forwarded-For even if configured."""
    settings = get_settings()
    monkeypatch.setattr(settings, "TRUSTED_PROXIES", ["10.0.0.1"])

    # Request comes from untrusted 192.168.1.100 attempting to spoof X-Forwarded-For
    req = MockRequest(
        client_host="192.168.1.100",
        headers={"X-Forwarded-For": "1.1.1.1"}
    )
    ip = _get_client_ip(req)
    assert ip == "192.168.1.100"
