"""Manual diagnostic: probe which Gemini models the configured API key can access.

Run directly:  python server/check_gemini_models.py

This is a developer utility, not a unit test. It was previously named
test_models.py, which caused pytest to auto-collect it and abort the entire
test run at import time when GEMINI_API_KEY was unset.
"""

import os
import sys

from dotenv import load_dotenv

MODELS_TO_TRY = [
    "gemini-2.0-flash-lite",
    "gemini-2.0-flash",
    "gemini-1.5-flash-8b",
    "gemini-1.5-flash-001",
    "gemini-1.5-pro",
]


def main() -> int:
    load_dotenv()
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        print("GEMINI_API_KEY is not set. Copy server/.env.example to server/.env "
              "and add a key before running this diagnostic.")
        return 1

    try:
        from google import genai
    except ImportError:
        print("google-genai is not installed. Run: pip install -r server/requirements.txt")
        return 1

    client = genai.Client(api_key=api_key)
    for model_name in MODELS_TO_TRY:
        try:
            r = client.models.generate_content(
                model=model_name, contents="Say hello in one word."
            )
            print(f"WORKING: {model_name} -> {r.text.strip()[:50]}")
        except Exception as e:
            print(f"FAIL {model_name}: {str(e)[:150]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
