"""
backend/app/services/osint_service.py
OSINT enrichment: VirusTotal, WHOIS, URL/phone/email analysis.
Designed to never block or crash the main analysis pipeline.
"""

from __future__ import annotations

import asyncio
import hashlib
import re
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional

import httpx

from app.core.config import get_settings
from app.core.logging import get_logger
from app.schemas.response import OsintDetail
from app.utils.text_utils import extract_domain, extract_urls, is_shortened_url

logger = get_logger(__name__)

# ── Disposable email domains (sample) ─────────────────────────────────────────
_DISPOSABLE_DOMAINS = frozenset({
    "mailinator.com", "guerrillamail.com", "tempmail.com", "throwam.com",
    "sharklasers.com", "yopmail.com", "trashmail.com", "getairmail.com",
    "dispostable.com", "mailnull.com",
})

_EMAIL_RE = re.compile(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}", re.IGNORECASE)
_PHONE_IN_RE = re.compile(r"(\+91|0)?[6-9]\d{9}")


@dataclass
class OsintScore:
    """Internal OSINT scoring before merging into the final score."""
    score: int = 0
    detail: OsintDetail = field(default_factory=OsintDetail)


class SimpleCache:
    """
    In-memory TTL cache for OSINT results.
    Falls back gracefully if Redis is unavailable.
    """

    def __init__(self, ttl: int = 3600) -> None:
        self._store: Dict[str, tuple[float, OsintScore]] = {}
        self._ttl = ttl

    def get(self, key: str) -> Optional[OsintScore]:
        entry = self._store.get(key)
        if entry and (time.monotonic() - entry[0]) < self._ttl:
            return entry[1]
        return None

    def set(self, key: str, value: OsintScore) -> None:
        self._store[key] = (time.monotonic(), value)

    def clear_expired(self) -> None:
        now = time.monotonic()
        self._store = {k: v for k, v in self._store.items() if now - v[0] < self._ttl}


class OsintService:
    """
    OSINT enrichment service.

    All methods are designed to:
    - Complete within the configured timeout
    - Return empty/zero results on any error
    - Never raise exceptions to the caller
    """

    def __init__(self) -> None:
        self._settings = get_settings()
        self._cache = SimpleCache(ttl=self._settings.OSINT_CACHE_TTL)

    async def analyze(self, text: str) -> OsintScore:
        """
        Run all OSINT checks on the text.

        Returns an OsintScore with score 0-100 and enrichment details.
        """
        try:
            return await asyncio.wait_for(
                self._run_checks(text),
                timeout=self._settings.OSINT_TIMEOUT,
            )
        except asyncio.TimeoutError:
            logger.warning("OSINT analysis timed out", extra={"timeout": self._settings.OSINT_TIMEOUT})
            return OsintScore()
        except Exception as exc:
            logger.error("OSINT analysis failed unexpectedly", extra={"error": str(exc)})
            return OsintScore()

    async def _run_checks(self, text: str) -> OsintScore:
        """Run URL, email, and phone checks concurrently."""
        urls = extract_urls(text)
        emails = _EMAIL_RE.findall(text)
        phones = _PHONE_IN_RE.findall(text)

        osint_score = OsintScore()
        osint_score.detail.urls_found = urls

        tasks = []

        # VirusTotal URL checks (run concurrently, limit to 3 URLs)
        for url in urls[:3]:
            tasks.append(self._check_url_virustotal(url, osint_score))

        # WHOIS check for first URL's domain
        if urls:
            tasks.append(self._check_whois(urls[0], osint_score))

        # Email validation
        for email in emails[:3]:
            tasks.append(self._validate_email(email, osint_score))

        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

        # Shortened URL heuristic (doesn't need API)
        for url in urls:
            if is_shortened_url(url):
                osint_score.score = min(100, osint_score.score + 20)
                break

        # Phone number signal
        if phones and text:
            osint_score.score = min(100, osint_score.score + 5)

        osint_score.detail.osint_score = osint_score.score
        return osint_score

    async def _check_url_virustotal(self, url: str, result: OsintScore) -> None:
        """Check a URL against VirusTotal. Silently skips if API key not set."""
        if not self._settings.virustotal_available:
            return

        cache_key = f"vt:{hashlib.md5(url.encode()).hexdigest()}"
        cached = self._cache.get(cache_key)
        if cached:
            result.score = min(100, result.score + cached.score)
            return

        try:
            url_id = hashlib.sha256(url.encode()).hexdigest()
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(
                    f"https://www.virustotal.com/api/v3/urls/{url_id}",
                    headers={"x-apikey": self._settings.VIRUSTOTAL_API_KEY},
                )
            if resp.status_code == 200:
                data = resp.json()
                stats = data.get("data", {}).get("attributes", {}).get("last_analysis_stats", {})
                malicious = stats.get("malicious", 0)
                suspicious = stats.get("suspicious", 0)
                if malicious > 0 or suspicious > 0:
                    pts = min(40, (malicious * 8) + (suspicious * 4))
                    result.score = min(100, result.score + pts)
                    result.detail.malicious_urls.append(url)
                    result.detail.virustotal_checked = True
                    score_entry = OsintScore(score=pts)
                    self._cache.set(cache_key, score_entry)
                    logger.info(
                        "VirusTotal: malicious URL detected",
                        extra={"url": url[:80], "malicious": malicious, "suspicious": suspicious},
                    )
        except Exception as exc:
            logger.debug("VirusTotal check failed", extra={"url": url[:80], "error": str(exc)[:100]})

    async def _check_whois(self, url: str, result: OsintScore) -> None:
        """Check WHOIS domain age. New domains (<30 days) are flagged."""
        domain = extract_domain(url)
        if not domain:
            return

        cache_key = f"whois:{domain}"
        cached = self._cache.get(cache_key)
        if cached:
            result.detail.whois_domain_age_days = cached.detail.whois_domain_age_days
            result.detail.whois_registrar = cached.detail.whois_registrar
            result.score = min(100, result.score + cached.score)
            return

        try:
            loop = asyncio.get_running_loop()

            def _sync_whois() -> Optional[dict]:
                try:
                    import whois  # type: ignore
                    w = whois.whois(domain)
                    return {"creation_date": w.creation_date, "registrar": w.registrar}
                except Exception:
                    return None

            info = await asyncio.wait_for(
                loop.run_in_executor(None, _sync_whois),
                timeout=4.0,
            )

            if info:
                from datetime import datetime, timezone
                creation = info.get("creation_date")
                if isinstance(creation, list):
                    creation = creation[0]
                if creation:
                    if hasattr(creation, "tzinfo") and creation.tzinfo is None:
                        creation = creation.replace(tzinfo=timezone.utc)
                    age_days = (datetime.now(timezone.utc) - creation).days
                    result.detail.whois_domain_age_days = age_days
                    result.detail.whois_registrar = str(info.get("registrar", ""))[:100]

                    if age_days < 30:
                        pts = 25
                        result.score = min(100, result.score + pts)
                        self._cache.set(cache_key, OsintScore(score=pts, detail=result.detail))
                        logger.info(
                            "WHOIS: newly registered domain",
                            extra={"domain": domain, "age_days": age_days},
                        )

        except (asyncio.TimeoutError, Exception) as exc:
            logger.debug("WHOIS check failed", extra={"domain": domain, "error": str(exc)[:100]})

    async def _validate_email(self, email: str, result: OsintScore) -> None:
        """Flag disposable email domains."""
        try:
            domain = email.split("@", 1)[1].lower()
            if domain in _DISPOSABLE_DOMAINS:
                result.score = min(100, result.score + 15)
                logger.info("Disposable email domain detected", extra={"domain": domain})
        except Exception:
            pass


# Module-level singleton
osint_service = OsintService()
