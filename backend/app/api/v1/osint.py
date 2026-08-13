"""
backend/app/api/v1/osint.py
Threat-intelligence lookup endpoints proxied for the Flutter client.

The mobile app never holds third-party API keys; these routes apply them
server-side. Each endpoint intentionally returns a ``checked`` flag so the
client can distinguish "verified clean" from "could not verify".

Contracts match lib/services/osint_service.dart:
    GET  /osint/hash/{hash}   → {checked, malicious, note, ...}
    POST /osint/urls          → {results: [{checked, malicious, note, ...}]}
    GET  /osint/ip/{ip}       → {checked, abuseConfidenceScore, note, ...}
"""

from __future__ import annotations

import re

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.core.db import get_db
from app.core.logging import get_logger
from app.middleware.api_auth import get_api_client
from app.services.osint import OSINTService
from sqlalchemy.ext.asyncio import AsyncSession

logger = get_logger(__name__)
router = APIRouter(prefix="/osint", tags=["OSINT"])

_IPV4_RE = re.compile(r"^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$")
_HASH_RE = re.compile(r"^[0-9a-fA-F]{32}([0-9a-fA-F]{32}|[0-9a-fA-F]{8})?$")


class UrlsRequest(BaseModel):
    urls: list[str] = Field(..., min_length=1, max_length=20)


def _hash_kind(hash_str: str) -> str | None:
    lowered = hash_str.lower()
    if not _HASH_RE.match(lowered):
        return None
    if len(lowered) == 32:
        return "md5"
    if len(lowered) == 40:
        return "sha1"
    if len(lowered) == 64:
        return "sha256"
    return None


@router.get("/hash/{file_hash}", summary="VirusTotal file-hash lookup")
async def check_hash(
    file_hash: str,
    db: AsyncSession = Depends(get_db),
    client: str | None = Depends(get_api_client),
) -> dict:
    kind = _hash_kind(file_hash)
    if kind is None:
        raise HTTPException(status_code=422, detail="hash must be a 32/40/64-char hex string (md5/sha1/sha256)")

    service = OSINTService(db)
    result = await service.analyze_hash(file_hash.lower())
    vt = result.get("virustotal", {})
    status = vt.get("status")

    if status == "success":
        return {
            "checked": True,
            "malicious": vt.get("malicious", 0),
            "suspicious": vt.get("suspicious", 0),
            "undetected": vt.get("undetected", 0),
            "hash_type": kind,
            "link": vt.get("link"),
            "note": f"{vt.get('malicious', 0)} security vendor(s) flagged this file as malicious.",
        }
    if status == "not_found":
        return {
            "checked": True,
            "malicious": 0,
            "hash_type": kind,
            "note": "Not seen by VirusTotal — no known positives, but also not a clean bill of health.",
        }
    return {
        "checked": False,
        "malicious": 0,
        "hash_type": kind,
        "note": "VirusTotal lookup unavailable (no API key configured or provider error).",
    }


@router.post("/urls", summary="Google Safe Browsing URL lookup")
async def check_urls(
    body: UrlsRequest,
    db: AsyncSession = Depends(get_db),
    client: str | None = Depends(get_api_client),
) -> dict:
    service = OSINTService(db)
    result = await service.analyze_urls(body.urls)
    gsb = result.get("google_safe_browsing", {})

    if gsb.get("status") == "success":
        details = gsb.get("details", [])
        flagged = {d.get("threat", {}).get("url") for d in details}
        results = [
            {
                "checked": True,
                "malicious": url in flagged,
                "note": "Flagged as dangerous by Google Safe Browsing."
                if url in flagged
                else "No threats found by Google Safe Browsing.",
            }
            for url in body.urls
        ]
        return {"results": results}

    return {
        "results": [
            {
                "checked": False,
                "malicious": False,
                "note": "Safe Browsing lookup unavailable (no API key configured or provider error).",
            }
            for _ in body.urls
        ]
    }


@router.get("/ip/{ip}", summary="AbuseIPDB IP lookup")
async def check_ip(
    ip: str,
    db: AsyncSession = Depends(get_db),
    client: str | None = Depends(get_api_client),
) -> dict:
    if not _IPV4_RE.match(ip):
        raise HTTPException(status_code=422, detail="invalid IPv4 address")

    service = OSINTService(db)
    result = await service.analyze_ip(ip)
    abuse = result.get("abuseipdb", {})

    if abuse.get("status") == "success":
        score = int(abuse.get("abuseConfidenceScore", 0))
        return {
            "checked": True,
            "abuseConfidenceScore": score,
            "totalReports": abuse.get("totalReports", 0),
            "isWhitelisted": abuse.get("isWhitelisted", False),
            "usageType": abuse.get("usageType", ""),
            "note": f"Abuse confidence score: {score}%",
        }
    return {
        "checked": False,
        "abuseConfidenceScore": 0,
        "note": "AbuseIPDB lookup unavailable (no API key configured or provider error).",
    }
