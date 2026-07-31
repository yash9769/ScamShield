"""
backend/app/services/ocr_service.py
Image OCR service using EasyOCR (CPU-only by default, optional GPU).
Supports JPG, PNG, BMP, GIF, WebP and PDF (via pdf2image).
"""

from __future__ import annotations

import asyncio
import time
from pathlib import Path
from typing import Optional

from app.core.config import get_settings
from app.core.exceptions import OCRError
from app.core.logging import get_logger

logger = get_logger(__name__)


class OCRService:
    """
    Extracts text from images using EasyOCR.

    The reader is loaded lazily on first use to avoid slowing startup.
    Supports multi-language OCR (default: English + Hindi).
    """

    def __init__(self) -> None:
        self._settings = get_settings()
        self._reader = None
        self._reader_loaded = False
        self._available = False
        self._load_error: Optional[str] = None

    def _ensure_reader(self) -> bool:
        """Lazily initialise the EasyOCR reader. Returns True if ready."""
        if self._reader_loaded:
            return self._available

        try:
            import easyocr  # type: ignore

            logger.info(
                "Initialising EasyOCR reader",
                extra={
                    "languages": self._settings.OCR_LANGUAGES,
                    "gpu": self._settings.OCR_GPU,
                },
            )
            t0 = time.monotonic()
            self._reader = easyocr.Reader(
                self._settings.OCR_LANGUAGES,
                gpu=self._settings.OCR_GPU,
                verbose=False,
            )
            elapsed = time.monotonic() - t0
            self._available = True
            logger.info(
                "EasyOCR reader initialised",
                extra={"load_time_s": round(elapsed, 2), "languages": self._settings.OCR_LANGUAGES},
            )
        except ImportError:
            self._load_error = "easyocr not installed"
            logger.warning("EasyOCR not available: easyocr not installed")
        except Exception as exc:
            self._load_error = str(exc)
            logger.error("Failed to initialise EasyOCR reader", extra={"error": str(exc)})
        finally:
            self._reader_loaded = True

        return self._available

    @property
    def available(self) -> bool:
        """Return True if EasyOCR is installed and the reader is ready."""
        return self._ensure_reader()

    async def extract_text(self, image_path: Path) -> tuple[str, float]:
        """
        Extract text from an image or PDF file.

        Args:
            image_path: Path to a temporary image or PDF file on disk.

        Returns:
            Tuple of (extracted_text, average_confidence 0-1).

        Raises:
            OCRError: If OCR is not available or extraction fails.
        """
        suffix = image_path.suffix.lower()

        if suffix == ".pdf":
            return await self._extract_from_pdf(image_path)

        return await self._extract_from_image(image_path)

    async def _extract_from_image(self, image_path: Path) -> tuple[str, float]:
        """Run EasyOCR on a raster image file."""
        if not self._ensure_reader():
            raise OCRError(
                f"EasyOCR is not available: {self._load_error}",
                filename=image_path.name,
            )

        loop = asyncio.get_running_loop()

        def _sync_ocr() -> tuple[str, float]:
            logger.info(
                "Running OCR on image",
                extra={"file": image_path.name, "size_bytes": image_path.stat().st_size},
            )
            t0 = time.monotonic()
            results = self._reader.readtext(str(image_path), detail=1, paragraph=False)
            elapsed = time.monotonic() - t0

            if not results:
                return "", 0.0

            texts = []
            confidences = []
            for bbox, text, confidence in results:
                if confidence > 0.3 and text.strip():
                    texts.append(text.strip())
                    confidences.append(confidence)

            extracted = " ".join(texts)
            avg_confidence = sum(confidences) / len(confidences) if confidences else 0.0

            logger.info(
                "OCR complete",
                extra={
                    "file": image_path.name,
                    "duration_s": round(elapsed, 2),
                    "chars_extracted": len(extracted),
                    "avg_confidence": round(avg_confidence, 3),
                    "text_blocks": len(results),
                },
            )
            return extracted, avg_confidence

        try:
            text, confidence = await loop.run_in_executor(None, _sync_ocr)
        except Exception as exc:
            logger.error(
                "OCR extraction failed",
                extra={"file": image_path.name, "error": str(exc)},
            )
            raise OCRError(
                f"OCR extraction failed: {exc}",
                filename=image_path.name,
            ) from exc

        if not text:
            raise OCRError(
                "No text could be extracted from the image. "
                "Please ensure the image contains readable text.",
                filename=image_path.name,
            )

        return text, confidence

    async def _extract_from_pdf(self, pdf_path: Path) -> tuple[str, float]:
        """Convert PDF pages to images, then run OCR on each page."""
        loop = asyncio.get_running_loop()

        def _sync_pdf_ocr() -> tuple[str, float]:
            try:
                from pdf2image import convert_from_path  # type: ignore
            except ImportError:
                raise OCRError(
                    "pdf2image not installed. Install with: pip install pdf2image",
                    filename=pdf_path.name,
                )

            if not self._ensure_reader():
                raise OCRError(
                    f"EasyOCR is not available: {self._load_error}",
                    filename=pdf_path.name,
                )

            logger.info("Converting PDF to images", extra={"file": pdf_path.name})
            # Process max 5 pages to keep latency reasonable
            pages = convert_from_path(str(pdf_path), dpi=200, last_page=5)

            all_texts = []
            all_confidences = []

            for i, page in enumerate(pages):
                import numpy as np
                page_array = np.array(page)
                results = self._reader.readtext(page_array, detail=1, paragraph=False)
                for _, text, confidence in results:
                    if confidence > 0.3 and text.strip():
                        all_texts.append(text.strip())
                        all_confidences.append(confidence)

            extracted = " ".join(all_texts)
            avg_confidence = sum(all_confidences) / len(all_confidences) if all_confidences else 0.0
            logger.info(
                "PDF OCR complete",
                extra={"pages": len(pages), "chars": len(extracted)},
            )
            return extracted, avg_confidence

        try:
            text, confidence = await loop.run_in_executor(None, _sync_pdf_ocr)
        except OCRError:
            raise
        except Exception as exc:
            raise OCRError(f"PDF OCR failed: {exc}", filename=pdf_path.name) from exc

        if not text:
            raise OCRError(
                "No text could be extracted from the PDF.",
                filename=pdf_path.name,
            )
        return text, confidence

    def get_status(self) -> dict:
        """Return the current status of the OCR service."""
        return {
            "available": self._available,
            "languages": self._settings.OCR_LANGUAGES if self._available else [],
            "gpu": self._settings.OCR_GPU,
            "error": self._load_error,
        }


# Module-level singleton (reader loaded lazily on first request)
ocr_service = OCRService()
