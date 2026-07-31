"""
backend/app/core/logging.py
Structured JSON logging configuration for ScamShield.
"""

from __future__ import annotations

import logging
import sys
import uuid
from contextvars import ContextVar
from typing import Any

# Context variable to hold the current request ID
request_id_var: ContextVar[str] = ContextVar("request_id", default="")


class JSONFormatter(logging.Formatter):
    """Format log records as single-line JSON for easy ingestion."""

    def format(self, record: logging.LogRecord) -> str:
        import json
        import traceback

        log_data: dict[str, Any] = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
        }

        # Attach request_id if present
        rid = request_id_var.get("")
        if rid:
            log_data["request_id"] = rid

        # Attach extra fields
        for key, value in record.__dict__.items():
            if key not in (
                "args", "asctime", "created", "exc_info", "exc_text", "filename",
                "funcName", "id", "levelname", "levelno", "lineno", "module",
                "msecs", "message", "msg", "name", "pathname", "process",
                "processName", "relativeCreated", "stack_info", "thread", "threadName",
            ):
                log_data[key] = value

        if record.exc_info:
            log_data["exception"] = traceback.format_exception(*record.exc_info)

        return json.dumps(log_data, default=str)


def setup_logging(level: str = "INFO") -> None:
    """Configure root logger with structured JSON output."""
    root_logger = logging.getLogger()
    root_logger.setLevel(getattr(logging, level, logging.INFO))

    # Remove any existing handlers
    root_logger.handlers.clear()

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())
    root_logger.addHandler(handler)

    # Silence noisy third-party loggers
    for noisy in ("uvicorn.access", "httpx", "httpcore"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


def get_logger(name: str) -> logging.Logger:
    """Return a named logger."""
    return logging.getLogger(name)


def generate_request_id() -> str:
    """Generate a short unique request ID."""
    return uuid.uuid4().hex[:12]
