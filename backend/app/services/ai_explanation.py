import os
import logging
import httpx
from typing import Dict, Any

logger = logging.getLogger(__name__)

GROQ_MODELS = ["llama-3.3-70b-versatile", "llama-3.1-70b-versatile"]

class AIExplanationService:
    def __init__(self):
        # Accept Groq key from GROQ_API_KEY or GEMINI_API_KEY (if it starts with gsk_)
        groq_key = os.getenv("GROQ_API_KEY", "").strip()
        gemini_key = os.getenv("GEMINI_API_KEY", "").strip()

        if groq_key:
            self.api_key = groq_key
            self.provider = "groq"
        elif gemini_key.startswith("gsk_"):
            self.api_key = gemini_key
            self.provider = "groq"
        elif gemini_key:
            self.api_key = gemini_key
            self.provider = "gemini"
        else:
            self.api_key = None
            self.provider = None

    async def generate_explanation(self, risk_data: Dict[str, Any], analysis_data: Dict[str, Any]) -> str:
        if not self.api_key:
            return "AI Explanation unavailable due to missing API key."

        risk_level = risk_data.get("level")
        risk_details = "\n".join(risk_data.get("details", []))

        prompt = f"""You are a Mobile Security Expert analyzing an Android application for a user of the ScamShield app.

The application was scanned and found to have a risk level of {risk_level}.

Here are the key findings that contributed to this risk:
{risk_details}

Please provide a short, easy-to-understand explanation (max 3-4 sentences) of why this app might be dangerous and what these findings mean together.
Focus on the practical implications for the user's privacy and security."""

        if self.provider == "groq":
            return await self._call_groq(prompt)
        return await self._call_gemini(prompt)

    async def _call_groq(self, prompt: str) -> str:
        """Call Groq API using httpx (OpenAI-compatible endpoint)."""
        for model in GROQ_MODELS:
            try:
                async with httpx.AsyncClient(timeout=15.0) as client:
                    response = await client.post(
                        "https://api.groq.com/openai/v1/chat/completions",
                        headers={
                            "Authorization": f"Bearer {self.api_key}",
                            "Content-Type": "application/json",
                        },
                        json={
                            "model": model,
                            "messages": [
                                {"role": "user", "content": prompt}
                            ],
                            "temperature": 0.3,
                            "max_tokens": 256,
                        },
                    )
                response.raise_for_status()
                return response.json()["choices"][0]["message"]["content"].strip()
            except Exception as e:
                logger.error(f"Groq explanation failed ({model}): {e}")
        return "Failed to generate AI explanation."

    async def _call_gemini(self, prompt: str) -> str:
        """Call Gemini API."""
        try:
            from google import genai
            from google.genai import types
            client = genai.Client(api_key=self.api_key)
            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=prompt,
                config=types.GenerateContentConfig(temperature=0.3),
            )
            return response.text
        except Exception as e:
            logger.error(f"Gemini explanation failed: {e}")
            return "Failed to generate AI explanation."
