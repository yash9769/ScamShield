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

# ── Sentry crash reporting (optional) ────────────────────────────────────────
# Active only when SENTRY_DSN is set in the environment. A missing DSN is a
# silent no-op — no exception, no warning, no performance overhead.
if settings.SENTRY_DSN:
    import sentry_sdk
    from sentry_sdk.integrations.fastapi import FastApiIntegration
    from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration

    sentry_sdk.init(
        dsn=settings.SENTRY_DSN,
        integrations=[FastApiIntegration(), SqlalchemyIntegration()],
        traces_sample_rate=0.05,   # 5% of requests get performance tracing
        send_default_pii=False,    # Never capture user IPs or emails
        environment="production",
    )
    logger.info("Sentry crash reporting initialised", extra={"dsn_set": True})

# Confirm key-sensitive configuration at boot — never log the actual key value.
logger.info(
    "ScamShield API configuration loaded",
    extra={
        "admin_key_set": bool(settings.ADMIN_API_KEY),
        "api_auth_enabled": settings.API_AUTH_ENABLED,
        "gemini_configured": settings.gemini_available,
        "allowed_origins_count": len(settings.ALLOWED_ORIGINS),
    },
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Schema management. In DEBUG (local dev) we keep create_all() for zero-
    # friction iteration; in production every change ships as a real Alembic
    # migration and is applied on boot by migrations.run_migrations().
    if settings.DEBUG:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
            # Lightweight additive upgrade for dev DBs created before the
            # scan-ownership column existed (ALTER ... IF NOT EXISTS is
            # Postgres-only; SQLite and other engines just skip it).
            try:
                from sqlalchemy import text
                await conn.execute(text(
                    "ALTER TABLE scans ADD COLUMN IF NOT EXISTS owner VARCHAR(64)"
                ))
            except Exception as exc:
                logger.debug("Optional dev migration skipped: %s", exc)
        logger.info("Database tables initialized (create_all, DEBUG mode)")
    else:
        from app.services.migrations import run_migrations

        run_migrations()
    yield
    # Dispose engine on shutdown
    await engine.dispose()

def create_app() -> FastAPI:
    """Application factory — creates and configures the FastAPI instance."""

    # /docs, /redoc and /openapi.json are OFF in production by default to avoid
    # exposing the full route surface (admin endpoints included). Turn them on
    # with ENABLE_DOCS=true, or automatically when DEBUG=true.
    docs_enabled = settings.ENABLE_DOCS or settings.DEBUG

    app = FastAPI(
        title=settings.APP_NAME,
        version=settings.VERSION,
        lifespan=lifespan,
        docs_url="/docs" if docs_enabled else None,
        redoc_url="/redoc" if docs_enabled else None,
        openapi_url="/openapi.json" if docs_enabled else None,
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
        contact={
            "name": "ScamShield",
            "url": "https://github.com/scamshield",
        },
        license_info={
            "name": "MIT",
        },
    )

    # ── Middleware ────────────────────────────────────────────────────────────

    # CORS — restrict in production via ALLOWED_ORIGINS env var
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.ALLOWED_ORIGINS,
        allow_credentials=False,
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

    # Legacy alias: the Flutter breach service calls /api/v1/breach while the
    # primary contract lives at /breach. Expose both so old clients keep working.
    from app.api.v1.breach import router as breach_router

    app.include_router(breach_router, prefix="/api/v1")

    # Root redirect
    @app.get("/", include_in_schema=False)
    async def root():
        payload: dict = {
            "service": settings.APP_NAME,
            "version": settings.VERSION,
            "status": "running",
            "health": "/health",
        }
        if docs_enabled:
            payload["docs"] = "/docs"
        return JSONResponse(content=payload)

    logger.info(
        "ScamShield API initialised",
        extra={"version": settings.VERSION, "debug": settings.DEBUG, "docs_enabled": docs_enabled},
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