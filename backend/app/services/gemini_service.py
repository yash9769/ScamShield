"""
backend/app/services/gemini_service.py
Gemini AI integration with retry logic, timeout handling, and graceful fallback.
"""

from __future__ import annotations

import asyncio
import json
import time
from typing import Optional
import httpx

from app.core.config import get_settings
from app.core.logging import get_logger
from app.models.enums import IconCategory, ScamCategory, ScamClassification
from app.schemas.response import AnalysisResult, DetectionReason
from app.utils.text_utils import extract_json, sanitize_text

logger = get_logger(__name__)

# ── System prompt ─────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """You are ScamShield AI, an elite cybersecurity analyst specialising in detecting
digital scams, phishing, fraud, and social engineering attacks targeting users in India and globally.

Analyse the provided message and return ONLY a valid JSON object with EXACTLY this structure:
{
  "classification": "safe" | "suspicious" | "scam",
  "riskScore": <integer 0-100>,
  "category": "Phishing" | "UPI Scam" | "Job Scam" | "Investment Scam" | "Lottery Scam" |
               "OTP Scam" | "Courier Scam" | "Government Scam" | "Bank Scam" | "Romance Scam" |
               "Fake QR Scam" | "Unknown" | "Safe",
  "confidence": <integer 0-100>,
  "reasons": [
    {
      "label": "<Short category label, max 5 words>",
      "description": "<Detailed explanation. Be specific about what you found.>",
      "scoreContribution": <integer 0-40>,
      "iconCategory": "financial" | "link" | "urgency" | "suspicious" | "manipulation" | "safe" |
                      "government" | "romance" | "crypto" | "job"
    }
  ],
  "summary": "<1-2 sentence verdict. Be direct and actionable.>",
  "recommended_action": "No action required. Message appears safe." |
                        "Be cautious. Verify the sender before responding." |
                        "Do NOT respond. Block and report this message." |
                        "Block the sender immediately and report to authorities."
}

Classification rules:
- "safe" → riskScore 0-30. No real threat signals.
- "suspicious" → riskScore 31-65. Some red flags but not conclusive.
- "scam" → riskScore 66-100. Clear scam indicators.

Look for: OTP/PIN requests, phishing URLs, fake prize/lottery wins, urgency/pressure tactics,
impersonation of banks/government/courts, requests for financial info (UPI/KYC/Aadhaar/PAN),
psychological manipulation (fear, greed), shortened links, poor grammar, crypto investment schemes,
fake job offers, romance scam signals, courier/delivery fee demands, QR code payment scams.

India-specific signals: UPI IDs (format: name@bank), Aadhaar numbers, PAN card requests,
NEFT/RTGS mentions, CBDt/Income Tax impersonation, RBI impersonation.

If safe: give one reason with iconCategory "safe" explaining it looks legitimate.
Return ONLY the raw JSON. No markdown. No explanation. No code fences."""


class GeminiService:
    """
    Async Gemini API service with model waterfall, retry, and timeout.

    Returns None on any failure — never propagates exceptions to callers.
    """

    def __init__(self) -> None:
        self._settings = get_settings()
        self._client = None
        self._genai_types = None
        self._available = False
        self._is_groq = False
        self._init_client()

    def _init_client(self) -> None:
        """Initialise the LLM client (Gemini or Groq)."""
        # 1. Check if we should use Groq
        if self._settings.groq_available:
            self._is_groq = True
            self._available = True
            logger.info("Groq client initialised", extra={"models": self._settings.GROQ_MODELS})
            return

        # 2. Check if we should use Gemini
        if not self._settings.gemini_available:
            logger.info("Neither Gemini nor Groq API keys configured — running in heuristic-only mode")
            return
        try:
            from google import genai
            from google.genai import types as genai_types

            self._client = genai.Client(api_key=self._settings.GEMINI_API_KEY)
            self._genai_types = genai_types
            self._available = True
            logger.info("Gemini client initialised", extra={"models": self._settings.GEMINI_MODELS})
        except ImportError:
            logger.warning("google-genai SDK not installed — running in heuristic-only mode")
        except Exception as exc:
            logger.error("Failed to initialise Gemini client", extra={"error": str(exc)})

    @property
    def available(self) -> bool:
        """Return True if Gemini is configured and ready."""
        return self._available

    async def analyze(self, text: str) -> Optional[AnalysisResult]:
        """
        Analyse text with Groq or Gemini AI.

        Tries each configured model in order.
        Returns None if all models fail or quota is exhausted.
        """
        if not self._available:
            return None

        clean_text = sanitize_text(text)

        if self._is_groq:
            for model_name in self._settings.GROQ_MODELS:
                result = await self._try_groq_model(model_name, clean_text)
                if result is not None:
                    return result
            logger.warning("All Groq models exhausted — falling back to heuristic")
            return None

        for model_name in self._settings.GEMINI_MODELS:
            result = await self._try_model(model_name, clean_text)
            if result is not None:
                return result

        logger.warning("All Gemini models exhausted — falling back to heuristic")
        return None

    async def _try_model(self, model_name: str, text: str) -> Optional[AnalysisResult]:
        """Attempt analysis with a single model, with retries and timeout."""
        for attempt in range(1, self._settings.GEMINI_MAX_RETRIES + 1):
            try:
                result = await asyncio.wait_for(
                    self._call_gemini(model_name, text),
                    timeout=self._settings.GEMINI_TIMEOUT,
                )
                logger.info(
                    "Gemini analysis complete",
                    extra={"model": model_name, "attempt": attempt, "score": result.riskScore},
                )
                return result

            except asyncio.TimeoutError:
                logger.warning(
                    "Gemini timeout",
                    extra={"model": model_name, "attempt": attempt,
                           "timeout": self._settings.GEMINI_TIMEOUT},
                )
                break  # Timeout — skip to next model

            except Exception as exc:
                err = str(exc)
                logger.warning(
                    "Gemini model error",
                    extra={"model": model_name, "attempt": attempt, "error": err[:200]},
                )
                # Quota / not-found errors → try next model immediately
                if any(sig in err.upper() for sig in ("QUOTA", "RESOURCE_EXHAUSTED", "NOT_FOUND", "404")):
                    break
                # Backoff for transient errors
                if attempt < self._settings.GEMINI_MAX_RETRIES:
                    await asyncio.sleep(0.5 * attempt)

        return None

    async def _try_groq_model(self, model_name: str, text: str) -> Optional[AnalysisResult]:
        """Attempt analysis with a single Groq model, with retries."""
        for attempt in range(1, self._settings.GEMINI_MAX_RETRIES + 1):
            try:
                result = await asyncio.wait_for(
                    self._call_groq(model_name, text),
                    timeout=self._settings.GEMINI_TIMEOUT,
                )
                logger.info(
                    "Groq analysis complete",
                    extra={"model": model_name, "attempt": attempt, "score": result.riskScore},
                )
                return result
            except asyncio.TimeoutError:
                logger.warning("Groq timeout", extra={"model": model_name, "attempt": attempt})
                break
            except Exception as exc:
                err = str(exc)
                logger.warning("Groq model error", extra={"model": model_name, "attempt": attempt, "error": err[:200]})
                if any(sig in err.upper() for sig in ("RATE_LIMIT", "QUOTA", "NOT_FOUND", "404")):
                    break
                if attempt < self._settings.GEMINI_MAX_RETRIES:
                    await asyncio.sleep(0.5 * attempt)
        return None

    async def _call_groq(self, model_name: str, text: str) -> AnalysisResult:
        """Make the actual Groq API call using httpx (OpenAI-compatible endpoint)."""
        # Resolve the Groq API key — accept it in either GROQ_API_KEY or GEMINI_API_KEY
        api_key = self._settings.GROQ_API_KEY or self._settings.GEMINI_API_KEY
        async with httpx.AsyncClient(timeout=self._settings.GEMINI_TIMEOUT) as client:
            response = await client.post(
                "https://api.groq.com/openai/v1/chat/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": model_name,
                    "messages": [
                        {"role": "system", "content": SYSTEM_PROMPT},
                        {"role": "user", "content": f"Analyse this message:\n\n{text}"},
                    ],
                    "temperature": self._settings.GEMINI_TEMPERATURE,
                    "response_format": {"type": "json_object"},
                    "max_tokens": 1024,
                },
            )
        response.raise_for_status()
        raw_text = response.json()["choices"][0]["message"]["content"]
        return self._parse_response(raw_text)

    async def _call_gemini(self, model_name: str, text: str) -> AnalysisResult:
        """Make the actual Gemini API call (runs in executor to avoid blocking)."""
        loop = asyncio.get_running_loop()

        def _sync_call() -> str:
            response = self._client.models.generate_content(
                model=model_name,
                contents=f"Analyse this message:\n\n{text}",
                config=self._genai_types.GenerateContentConfig(
                    system_instruction=SYSTEM_PROMPT,
                    response_mime_type="application/json",
                    temperature=self._settings.GEMINI_TEMPERATURE,
                ),
            )
            return response.text

        raw_text = await loop.run_in_executor(None, _sync_call)
        return self._parse_response(raw_text)

    def _parse_response(self, raw_text: str) -> AnalysisResult:
        """Parse and validate Gemini's JSON response into an AnalysisResult."""
        data = extract_json(raw_text)

        # Normalise riskScore
        data["riskScore"] = max(0, min(100, int(data.get("riskScore", 0))))
        data["confidence"] = max(0, min(100, int(data.get("confidence", 70))))
        data["aiPowered"] = True

        # Validate and sanitise icon categories
        valid_icons = {c.value for c in IconCategory}
        for reason in data.get("reasons", []):
            if reason.get("iconCategory") not in valid_icons:
                reason["iconCategory"] = "suspicious"
            reason["scoreContribution"] = max(0, min(40, int(reason.get("scoreContribution", 0))))

        # Validate classification
        valid_classifications = {c.value for c in ScamClassification}
        if data.get("classification") not in valid_classifications:
            data["classification"] = "suspicious"

        # Validate category
        valid_categories = {c.value for c in ScamCategory}
        if data.get("category") not in valid_categories:
            data["category"] = "Unknown"

        return AnalysisResult(**data)


# Module-level singleton — initialised once at import time
gemini_service = GeminiService()
