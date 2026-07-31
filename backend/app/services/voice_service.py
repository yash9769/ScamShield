"""
backend/app/services/voice_service.py
Audio transcription service using OpenAI Whisper (local, no API key needed).
"""

from __future__ import annotations

import asyncio
import time
from pathlib import Path
from typing import Optional

from app.core.config import get_settings
from app.core.exceptions import AudioProcessingError
from app.core.logging import get_logger

logger = get_logger(__name__)


class VoiceService:
    """
    Transcribes audio files using OpenAI's Whisper model running locally.

    The Whisper model is loaded lazily on first use to avoid slowing startup.
    """

    def __init__(self) -> None:
        self._settings = get_settings()
        self._model = None
        self._model_loaded = False
        self._available = False
        self._load_error: Optional[str] = None

    def _ensure_model(self) -> bool:
        """Lazily load the Whisper model. Returns True if ready."""
        if self._model_loaded:
            return self._available

        try:
            import whisper  # type: ignore

            logger.info("Loading Whisper model", extra={"model": self._settings.WHISPER_MODEL})
            t0 = time.monotonic()
            self._model = whisper.load_model(self._settings.WHISPER_MODEL)
            elapsed = time.monotonic() - t0
            self._available = True
            logger.info(
                "Whisper model loaded",
                extra={"model": self._settings.WHISPER_MODEL, "load_time_s": round(elapsed, 2)},
            )
        except ImportError:
            self._load_error = "openai-whisper not installed"
            logger.warning("Whisper not available: openai-whisper not installed")
        except Exception as exc:
            self._load_error = str(exc)
            logger.error("Failed to load Whisper model", extra={"error": str(exc)})
        finally:
            self._model_loaded = True

        return self._available

    @property
    def available(self) -> bool:
        """Return True if Whisper is installed and the model is loaded."""
        return self._ensure_model()

    async def transcribe(self, audio_path: Path) -> str:
        """
        Transcribe an audio file using Whisper.

        Args:
            audio_path: Path to a temporary audio file on disk.

        Returns:
            The transcribed text string.

        Raises:
            AudioProcessingError: If Whisper is not available or transcription fails.
        """
        if not self._ensure_model():
            raise AudioProcessingError(
                f"Whisper is not available: {self._load_error}",
                filename=audio_path.name,
            )

        loop = asyncio.get_running_loop()

        def _sync_transcribe() -> str:
            logger.info(
                "Transcribing audio",
                extra={"file": audio_path.name, "size_bytes": audio_path.stat().st_size},
            )
            t0 = time.monotonic()
            result = self._model.transcribe(
                str(audio_path),
                fp16=False,      # Safe for CPU-only environments
                language=None,   # Auto-detect language
                verbose=False,
            )
            elapsed = time.monotonic() - t0
            text = result.get("text", "").strip()
            logger.info(
                "Transcription complete",
                extra={
                    "file": audio_path.name,
                    "duration_s": round(elapsed, 2),
                    "transcript_length": len(text),
                    "detected_language": result.get("language", "unknown"),
                },
            )
            return text

        try:
            transcript = await loop.run_in_executor(None, _sync_transcribe)
        except Exception as exc:
            logger.error(
                "Whisper transcription failed",
                extra={"file": audio_path.name, "error": str(exc)},
            )
            raise AudioProcessingError(
                f"Transcription failed: {exc}",
                filename=audio_path.name,
            ) from exc

        if not transcript:
            raise AudioProcessingError(
                "No speech detected in the audio file. "
                "Please ensure the audio is clear and not silent.",
                filename=audio_path.name,
            )

        return transcript

    def get_status(self) -> dict:
        """Return the current status of the voice service."""
        return {
            "available": self._available,
            "model": self._settings.WHISPER_MODEL if self._available else None,
            "error": self._load_error,
        }


# Module-level singleton (model loaded lazily on first request)
voice_service = VoiceService()
