import os
import logging
from typing import Dict, Any
from google import genai
from google.genai import types

logger = logging.getLogger(__name__)

class AIExplanationService:
    def __init__(self):
        self.api_key = os.getenv("GEMINI_API_KEY")
        try:
            self.client = genai.Client(api_key=self.api_key)
        except Exception as e:
            logger.error(f"Failed to initialize Gemini Client: {e}")
            self.client = None

    async def generate_explanation(self, risk_data: Dict[str, Any], analysis_data: Dict[str, Any]) -> str:
        if not self.client:
            return "AI Explanation unavailable due to missing API key."

        try:
            risk_level = risk_data.get("level")
            risk_details = "\n".join(risk_data.get("details", []))
            
            prompt = f"""
            You are a Mobile Security Expert analyzing an Android application for a user of the ScamShield app.
            
            The application was scanned and found to have a risk level of {risk_level}.
            
            Here are the key findings that contributed to this risk:
            {risk_details}
            
            Please provide a short, easy-to-understand explanation (max 3-4 sentences) of why this app might be dangerous and what these findings mean together. 
            Focus on the practical implications for the user's privacy and security.
            """
            
            response = self.client.models.generate_content(
                model='gemini-2.5-flash',
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.3,
                )
            )
            return response.text
        except Exception as e:
            logger.error(f"Failed to generate AI explanation: {e}")
            return "Failed to generate AI explanation."
