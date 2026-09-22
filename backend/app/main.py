"""
backend/app/main.py
FastAPI application factory for ScamShield v2.
"""

from __future__ import annotations

import time

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager

from app.core.db import engine
from app.models.base import Base
# Import all models to ensure they are registered with Base
import app.models.schema

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.core.logging import generate_request_id, get_logger, request_id_var, setup_logging
from app.middleware.error_handler import register_error_handlers
from app.middleware.rate_limit import limiter, register_rate_limiter
from app.middleware.security_headers import SecurityHeadersMiddleware

# Initialise structured logging before anything else
settings = get_settings()
setup_logging(settings.LOG_LEVEL)
logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create all tables on startup
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    logger.info("Database tables initialized")
    yield
    # Dispose engine on shutdown
    await engine.dispose()

def create_app() -> FastAPI:
    """Application factory — creates and configures the FastAPI instance."""

    app = FastAPI(
        title=settings.APP_NAME,
        version=settings.VERSION,
        lifespan=lifespan,
        description=(
            "ScamShield API — Production-grade scam detection engine powered by "
            "Gemini AI, Whisper speech recognition, EasyOCR, and OSINT enrichment.\n\n"
            "## Features\n"
            "- **POST /analyze** — Text scam analysis (Gemini + heuristic + OSINT)\n"
            "- **POST /analyze-voice** — Audio transcription + scam analysis\n"
            "- **POST /analyze-image** — OCR + scam analysis (jpg, png, pdf)\n"
            "- **POST /analyze-batch** — Batch analysis of multiple messages\n"
            "- **GET /health** — Service health and downstream status\n\n"
            "All endpoints include automatic Gemini → heuristic fallback."
        ),
        docs_url="/docs",
        redoc_url="/redoc",
        openapi_url="/openapi.json",
        contact={
            "name": "ScamShield",
            "url": "https://github.com/scamshield",
        },
        license_info={
            "name": "MIT",
        },
    )

    # ── Middleware ────────────────────────────────────────────────────────────

    # CORS — restrict in production via ALLOWED_ORIGINS env var.
    # Wildcard origins ("*") combined with allow_credentials=True lets
    # CORSMiddleware reflect back any Origin header with credentials allowed,
    # so credentials are only enabled when an explicit origin list is configured.
    wildcard_origins = "*" in settings.ALLOWED_ORIGINS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.ALLOWED_ORIGINS,
        allow_credentials=not wildcard_origins,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["*"],
        max_age=600,
    )

    # Security headers
    app.add_middleware(SecurityHeadersMiddleware)

    # ── Rate limiting ─────────────────────────────────────────────────────────
    register_rate_limiter(app, limiter)

    # ── Error handlers ────────────────────────────────────────────────────────
    register_error_handlers(app)

    # ── Request ID + timing middleware ────────────────────────────────────────
    @app.middleware("http")
    async def request_middleware(request: Request, call_next):
        """Attach request ID and log request/response timing."""
        rid = generate_request_id()
        token = request_id_var.set(rid)
        t0 = time.monotonic()

        response = await call_next(request)

        elapsed_ms = round((time.monotonic() - t0) * 1000, 1)
        response.headers["X-Request-ID"] = rid
        response.headers["X-Response-Time"] = f"{elapsed_ms}ms"

        logger.info(
            "HTTP request",
            extra={
                "request_id": rid,
                "method": request.method,
                "path": str(request.url.path),
                "status_code": response.status_code,
                "duration_ms": elapsed_ms,
                "client_ip": request.client.host if request.client else "unknown",
            },
        )

        request_id_var.reset(token)
        return response

    # ── Routes ────────────────────────────────────────────────────────────────
    app.include_router(api_router)

    # Root redirect
    @app.get("/", include_in_schema=False)
    async def root():
        return JSONResponse(
            content={
                "service": settings.APP_NAME,
                "version": settings.VERSION,
                "status": "running",
                "docs": "/docs",
                "health": "/health",
            }
        )

    logger.info(
        "ScamShield API initialised",
        extra={"version": settings.VERSION, "debug": settings.DEBUG},
    )

    return app


# Application instance
app = create_app()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.DEBUG,
        log_level=settings.LOG_LEVEL.lower(),
        access_log=False,  # We handle access logging in middleware
    )
