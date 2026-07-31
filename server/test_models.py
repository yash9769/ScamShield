import os
import sys
from google import genai
from dotenv import load_dotenv

load_dotenv()
client = genai.Client(api_key=os.getenv('GEMINI_API_KEY'))

models_to_try = [
    'gemini-2.0-flash-lite',
    'gemini-2.0-flash',
    'gemini-1.5-flash-8b',
    'gemini-1.5-flash-001',
    'gemini-1.5-pro',
    'gemini-1.0-pro',
]

for model_name in models_to_try:
    try:
        r = client.models.generate_content(model=model_name, contents='Say hello in one word.')
        print(f'WORKING: {model_name} -> {r.text.strip()[:50]}')
    except Exception as e:
        err = str(e)[:150]
        print(f'FAIL {model_name}: {err}')
