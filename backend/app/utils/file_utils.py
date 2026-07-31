"""
backend/app/utils/file_utils.py
Temporary file management for audio and image uploads.
"""

from __future__ import annotations

import os
import tempfile
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncGenerator

import aiofiles

from app.core.logging import get_logger

logger = get_logger(__name__)

# Allowed MIME types and extensions
AUDIO_EXTENSIONS = frozenset({".mp3", ".wav", ".m4a", ".aac", ".ogg", ".flac"})
IMAGE_EXTENSIONS = frozenset({".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"})
PDF_EXTENSIONS = frozenset({".pdf"})

AUDIO_MIME_TYPES = frozenset(
    {"audio/mpeg", "audio/wav", "audio/x-wav", "audio/mp4", "audio/aac",
     "audio/ogg", "audio/flac", "audio/x-m4a"}
)
IMAGE_MIME_TYPES = frozenset(
    {"image/jpeg", "image/png", "image/gif", "image/bmp", "image/webp"}
)


@asynccontextmanager
async def temp_audio_file(
    data: bytes, original_filename: str
) -> AsyncGenerator[Path, None]:
    """
    Context manager that writes audio bytes to a named temp file,
    yields the Path, then deletes the file on exit.

    Usage:
        async with temp_audio_file(data, "voice.mp3") as path:
            transcript = whisper_model.transcribe(str(path))
    """
    suffix = Path(original_filename).suffix.lower() or ".tmp"
    tmp_path = Path(tempfile.gettempdir()) / f"scamshield_{uuid.uuid4().hex}{suffix}"

    try:
        async with aiofiles.open(tmp_path, "wb") as f:
            await f.write(data)
        logger.debug("Temp audio file created", extra={"path": str(tmp_path), "bytes": len(data)})
        yield tmp_path
    finally:
        try:
            if tmp_path.exists():
                os.remove(tmp_path)
                logger.debug("Temp audio file deleted", extra={"path": str(tmp_path)})
        except OSError as exc:
            logger.warning("Failed to delete temp file", extra={"path": str(tmp_path), "error": str(exc)})


@asynccontextmanager
async def temp_image_file(
    data: bytes, original_filename: str
) -> AsyncGenerator[Path, None]:
    """
    Context manager that writes image bytes to a named temp file,
    yields the Path, then deletes the file on exit.
    """
    suffix = Path(original_filename).suffix.lower() or ".tmp"
    tmp_path = Path(tempfile.gettempdir()) / f"scamshield_{uuid.uuid4().hex}{suffix}"

    try:
        async with aiofiles.open(tmp_path, "wb") as f:
            await f.write(data)
        logger.debug("Temp image file created", extra={"path": str(tmp_path), "bytes": len(data)})
        yield tmp_path
    finally:
        try:
            if tmp_path.exists():
                os.remove(tmp_path)
                logger.debug("Temp image file deleted", extra={"path": str(tmp_path)})
        except OSError as exc:
            logger.warning("Failed to delete temp file", extra={"path": str(tmp_path), "error": str(exc)})


def validate_audio_file(filename: str, content_type: str, size_bytes: int, max_bytes: int) -> None:
    """
    Validate an uploaded audio file.

    Raises:
        ValueError: with a user-friendly message if validation fails.
    """
    ext = Path(filename).suffix.lower()
    if ext not in AUDIO_EXTENSIONS:
        raise ValueError(
            f"Unsupported audio format '{ext}'. Supported: {', '.join(sorted(AUDIO_EXTENSIONS))}"
        )
    if size_bytes > max_bytes:
        raise ValueError(
            f"Audio file too large ({size_bytes / 1_048_576:.1f} MB). "
            f"Maximum allowed: {max_bytes / 1_048_576:.0f} MB"
        )


def validate_image_file(filename: str, content_type: str, size_bytes: int, max_bytes: int) -> None:
    """
    Validate an uploaded image file.

    Raises:
        ValueError: with a user-friendly message if validation fails.
    """
    ext = Path(filename).suffix.lower()
    allowed = IMAGE_EXTENSIONS | PDF_EXTENSIONS
    if ext not in allowed:
        raise ValueError(
            f"Unsupported image format '{ext}'. Supported: {', '.join(sorted(allowed))}"
        )
    if size_bytes > max_bytes:
        raise ValueError(
            f"Image file too large ({size_bytes / 1_048_576:.1f} MB). "
            f"Maximum allowed: {max_bytes / 1_048_576:.0f} MB"
        )
