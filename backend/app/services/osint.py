import logging
import httpx
import json
from typing import Dict, Any, List, Optional
from datetime import datetime, timedelta, timezone
from tenacity import retry, wait_exponential, stop_after_attempt, retry_if_exception_type

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.core.config import get_settings
from app.models.schema import CachedOSINT

logger = logging.getLogger(__name__)
settings = get_settings()

class RateLimitException(Exception):
    pass

class OSINTService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.vt_api_key = settings.VIRUSTOTAL_API_KEY
        self.gsb_api_key = settings.GOOGLE_SAFE_BROWSING_API_KEY
        self.abuseipdb_api_key = settings.ABUSEIPDB_API_KEY
        self.timeout = settings.OSINT_TIMEOUT

    async def _get_cache(self, indicator: str) -> Optional[Dict[str, Any]]:
        result = await self.db.execute(
            select(CachedOSINT).where(CachedOSINT.indicator == indicator)
        )
        cached = result.scalars().first()
        if cached:
            # Check expiration
            if cached.expires_at and cached.expires_at > datetime.now(timezone.utc):
                return cached.data
            else:
                # Expired
                await self.db.delete(cached)
                await self.db.commit()
        return None

    async def _set_cache(self, indicator: str, i_type: str, data: Dict[str, Any]):
        expires_at = datetime.now(timezone.utc) + timedelta(seconds=settings.OSINT_CACHE_TTL)
        cached = CachedOSINT(
            indicator=indicator,
            type=i_type,
            data=data,
            expires_at=expires_at
        )
        self.db.add(cached)
        try:
            await self.db.commit()
        except Exception as e:
            logger.error(f"Failed to save OSINT cache: {e}")
            await self.db.rollback()

    @retry(
        wait=wait_exponential(multiplier=1, min=2, max=10),
        stop=stop_after_attempt(3),
        retry=retry_if_exception_type(RateLimitException)
    )
    async def _fetch_virustotal(self, file_hash: str) -> Dict[str, Any]:
        if not self.vt_api_key:
            return {"status": "skipped", "reason": "No API key"}

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            headers = {"x-apikey": self.vt_api_key}
            response = await client.get(
                f"https://www.virustotal.com/api/v3/files/{file_hash}", 
                headers=headers
            )
            
            if response.status_code == 429:
                raise RateLimitException("VirusTotal Rate Limited")
                
            if response.status_code == 200:
                data = response.json()
                stats = data.get("data", {}).get("attributes", {}).get("last_analysis_stats", {})
                return {
                    "status": "success",
                    "malicious": stats.get("malicious", 0),
                    "suspicious": stats.get("suspicious", 0),
                    "undetected": stats.get("undetected", 0),
                    "link": f"https://www.virustotal.com/gui/file/{file_hash}"
                }
            elif response.status_code == 404:
                return {"status": "not_found"}
            else:
                logger.warning(f"VirusTotal API error: {response.status_code}")
                return {"status": "error", "code": response.status_code}

    async def analyze_hash(self, file_hash: str) -> Dict[str, Any]:
        """Checks VirusTotal for the given file hash with caching."""
        cached = await self._get_cache(file_hash)
        if cached:
            return {"virustotal": cached}

        try:
            vt_result = await self._fetch_virustotal(file_hash)
        except RateLimitException:
            vt_result = {"status": "RATE_LIMITED"}
        except Exception as e:
            logger.error(f"VT Error: {e}")
            vt_result = {"status": "error"}

        if vt_result.get("status") in ["success", "not_found", "RATE_LIMITED"]:
            await self._set_cache(file_hash, "file", vt_result)

        return {"virustotal": vt_result}

    @retry(
        wait=wait_exponential(multiplier=1, min=2, max=10),
        stop=stop_after_attempt(3),
        retry=retry_if_exception_type(RateLimitException)
    )
    async def _fetch_abuseipdb(self, ip: str) -> Dict[str, Any]:
        if not self.abuseipdb_api_key:
            return {"status": "skipped", "reason": "No API key"}

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.get(
                f"https://api.abuseipdb.com/api/v2/check",
                params={"ipAddress": ip, "maxAgeInDays": 90},
                headers={"Key": self.abuseipdb_api_key, "Accept": "application/json"},
            )

            if response.status_code == 429:
                raise RateLimitException("AbuseIPDB Rate Limited")

            if response.status_code == 200:
                data = response.json().get("data", {})
                return {
                    "status": "success",
                    "abuseConfidenceScore": data.get("abuseConfidenceScore", 0),
                    "isWhitelisted": data.get("isWhitelisted", False),
                    "totalReports": data.get("totalReports", 0),
                    "usageType": data.get("usageType", ""),
                }
            if response.status_code == 404:
                return {"status": "not_found"}
            logger.warning(f"AbuseIPDB API error: {response.status_code}")
            return {"status": "error", "code": response.status_code}

    async def analyze_ip(self, ip: str) -> Dict[str, Any]:
        """Checks AbuseIPDB for the given IP with caching."""
        cache_key = f"ip_{ip}"
        cached = await self._get_cache(cache_key)
        if cached:
            return {"abuseipdb": cached}

        try:
            result = await self._fetch_abuseipdb(ip)
        except RateLimitException:
            result = {"status": "RATE_LIMITED"}
        except Exception as e:
            logger.error(f"AbuseIPDB Error: {e}")
            result = {"status": "error"}

        if result.get("status") in ["success", "not_found", "RATE_LIMITED"]:
            await self._set_cache(cache_key, "ip", result)

        return {"abuseipdb": result}

    @retry(
        wait=wait_exponential(multiplier=1, min=2, max=10),
        stop=stop_after_attempt(3),
        retry=retry_if_exception_type(RateLimitException)
    )
    async def _fetch_gsb(self, urls: List[str]) -> Dict[str, Any]:
        if not self.gsb_api_key or not urls:
            return {"status": "skipped"}
            
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            payload = {
                "client": {"clientId": "scamshield", "clientVersion": "2.0"},
                "threatInfo": {
                    "threatTypes": ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE"],
                    "platformTypes": ["ANY_PLATFORM"],
                    "threatEntryTypes": ["URL"],
                    "threatEntries": [{"url": u} for u in urls]
                }
            }
            response = await client.post(
                f"https://safebrowsing.googleapis.com/v4/threatMatches:find?key={self.gsb_api_key}",
                json=payload
            )
            
            if response.status_code == 429:
                raise RateLimitException("GSB Rate Limited")
                
            if response.status_code == 200:
                data = response.json()
                matches = data.get("matches", [])
                return {
                    "status": "success",
                    "matches": len(matches),
                    "details": matches
                }
            return {"status": "error", "code": response.status_code}

    async def analyze_urls(self, urls: List[str]) -> Dict[str, Any]:
        """Checks Google Safe Browsing for URLs."""
        if not urls:
            return {}
            
        # For simplicity, we cache the whole list hash. In prod we'd cache per URL.
        cache_key = f"urls_{hash(tuple(sorted(urls)))}"
        cached = await self._get_cache(cache_key)
        if cached:
            return {"google_safe_browsing": cached}
            
        try:
            gsb_result = await self._fetch_gsb(urls)
        except RateLimitException:
            gsb_result = {"status": "RATE_LIMITED"}
        except Exception as e:
            logger.error(f"GSB Error: {e}")
            gsb_result = {"status": "error"}
            
        if gsb_result.get("status") in ["success", "RATE_LIMITED"]:
            await self._set_cache(cache_key, "domain", gsb_result)
            
        return {"google_safe_browsing": gsb_result}
