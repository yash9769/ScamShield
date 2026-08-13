"""
backend/app/middleware/api_auth.py
Authentication dependencies for protected endpoints.

Three layers:

1. ``verify_admin_auth`` — admin-only endpoints (/dashboard, /api/audit-logs).
   Accepts ``Authorization: Bearer <ADMIN_API_KEY>`` or ``X-Admin-Key: <key>``.

2. ``get_api_client`` — client auth for ALL sensitive endpoints
   (/analyze, /analyze-voice, /analyze-image, /analyze-batch, /scan*,
   /history, /breach, /osint/*). When ``API_AUTH_ENABLED`` is true, callers
   must present either an ``X-Device-Token`` (an anonymous per-install token
   generated on-device — never a hardcoded secret) or a server-side
   ``X-API-Key`` from API_KEYS.

3. ``ClientIdentity`` — a stable, non-reversible fingerprint of the
   presented credential. It is safe to log and to store as scan ownership
   without ever persisting the raw token.

When auth is disabled the dependency is a no-op, preserving the existing
open behaviour for self-hosted / trusted-network deployments.
"""

from __future__ import annotations

import hashlib
import hmac
from typing import Optional

from fastapi import HTTPException, Request

from app.core.config import get_settings


def credential_fingerprint(raw: str) -> str:
    """SHA-256 fingerprint of a credential, safe to store/log."""
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def _extract_bearer_or_key(request: Request) -> str:
    auth_header = request.headers.get("Authorization", "")
    api_key_header = request.headers.get("X-Admin-Key", "")
    if auth_header.startswith("Bearer "):
        return auth_header[7:].strip()
    if api_key_header:
        return api_key_header.strip()
    return ""


async def verify_admin_auth(request: Request) -> None:
    """Reject the request unless a valid admin credential is presented."""
    settings = get_settings()
    token = _extract_bearer_or_key(request)
    # Constant-time comparison so timing does not leak how much of the key
    # matches. hmac.compare_digest needs equal-length inputs; the hashed forms
    # are fixed-length and safe to compare.
    expected = hashlib.sha256(settings.ADMIN_API_KEY.encode()).digest()
    provided = hashlib.sha256(token.encode()).digest() if token else b""
    if not token or not hmac.compare_digest(provided, expected):
        raise HTTPException(
            status_code=401,
            detail=(
                "Unauthorized: Admin authentication required via "
                "'Authorization: Bearer <token>' or 'X-Admin-Key' header."
            ),
        )


async def get_api_client(request: Request) -> Optional[str]:
    """
    Validate client auth for every sensitive endpoint.

    Returns a stable credential fingerprint used for ownership checks and
    logging — never the raw token. Returns ``None`` when auth is disabled.
    """
    settings = get_settings()
    if not settings.API_AUTH_ENABLED:
        return None

    device_token = request.headers.get("X-Device-Token", "").strip()
    if len(device_token) >= 16:
        return credential_fingerprint(device_token)

    api_key = request.headers.get("X-API-Key", "").strip()
    if api_key and api_key in set(settings.API_KEYS):
        return f"key:{credential_fingerprint(api_key)}"

    raise HTTPException(
        status_code=401,
        detail=(
            "Unauthorized: this endpoint requires an X-Device-Token or a "
            "valid X-API-Key header."
        ),
    )
