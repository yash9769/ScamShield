"""
backend/app/middleware/error_handler.py
Global exception handler — translates all exceptions into structured JSON responses.
"""

from __future__ import annotations

import time
import traceback

from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse

from app.core.exceptions import (
    AudioProcessingError,
    OCRError,
    OsintTimeoutError,
    ScamShieldError,
    ValidationError,
)
from app.core.logging import get_logger, request_id_var

logger = get_logger(__name__)


def register_error_handlers(app: FastAPI) -> None:
    """Register all global exception handlers on the FastAPI app."""

    @app.exception_handler(ValidationError)
    async def handle_validation_error(request: Request, exc: ValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={
                "error": "Validation Error",
                "detail": exc.message,
                "request_id": request_id_var.get(""),
            },
        )

    @app.exception_handler(AudioProcessingError)
    async def handle_audio_error(request: Request, exc: AudioProcessingError) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={
                "error": "Audio Processing Error",
                "detail": exc.message,
                "filename": exc.filename,
                "request_id": request_id_var.get(""),
            },
        )

    @app.exception_handler(OCRError)
    async def handle_ocr_error(request: Request, exc: OCRError) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={
                "error": "OCR Error",
                "detail": exc.message,
                "filename": exc.filename,
                "request_id": request_id_var.get(""),
            },
        )

    @app.exception_handler(OsintTimeoutError)
    async def handle_osint_timeout(request: Request, exc: OsintTimeoutError) -> JSONResponse:
        # OSINT timeouts are non-fatal — this handler is a safety net
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "error": "OSINT Timeout",
                "detail": exc.message,
                "request_id": request_id_var.get(""),
            },
        )

    @app.exception_handler(ScamShieldError)
    async def handle_scamshield_error(request: Request, exc: ScamShieldError) -> JSONResponse:
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={
                "error": "Internal Error",
                "detail": exc.message,
                "request_id": request_id_var.get(""),
            },
        )

    @app.exception_handler(Exception)
    async def handle_unhandled_exception(request: Request, exc: Exception) -> JSONResponse:
        rid = request_id_var.get("")
        logger.error(
            "Unhandled exception",
            extra={
                "request_id": rid,
                "path": str(request.url.path),
                "method": request.method,
                "error": str(exc),
                "traceback": traceback.format_exc()[-2000:],
            },
        )
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={
                "error": "Internal Server Error",
                "detail": "An unexpected error occurred. Please try again.",
                "request_id": rid,
            },
        )
