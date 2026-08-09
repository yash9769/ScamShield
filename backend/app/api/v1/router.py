"""
backend/app/api/v1/router.py
Aggregates all v1 API routers into a single APIRouter.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1 import analyze, batch, health, image, voice, breach
from app.routes import scan

api_router = APIRouter()

# Mount all route modules
api_router.include_router(health.router, tags=["System"])
api_router.include_router(analyze.router, tags=["Analysis"])
api_router.include_router(voice.router, tags=["Analysis"])
api_router.include_router(image.router, tags=["Analysis"])
api_router.include_router(batch.router, tags=["Analysis"])
api_router.include_router(scan.router, tags=["Scan"])
api_router.include_router(breach.router, tags=["Breach"])

