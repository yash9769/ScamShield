"""
backend/app/api/v1/image.py
POST /analyze-image — image OCR + scam analysis.
"""

from fastapi import APIRouter, File, Request, UploadFile, status
from fastapi.responses import JSONResponse

from app.core.config import get_settings
from app.core.exceptions import OCRError
from app.core.logging import get_logger
from app.middleware.rate_limit import limiter
from app.schemas.response import ImageAnalysisResponse
from app.services.ai_engine import ai_engine
from app.services.ocr_service import ocr_service
from app.utils.file_utils import temp_image_file, validate_image_file

logger = get_logger(__name__)
router = APIRouter()


@router.post(
    "/analyze-image",
    response_model=ImageAnalysisResponse,
    summary="Analyse Image for Scam",
    description=(
        "Accepts an image file (jpg, jpeg, png, pdf), extracts text using EasyOCR, "
        "then runs full scam analysis on the extracted text. "
        "Supports English and Hindi text. Maximum file size: 10 MB."
    ),
    tags=["Analysis"],
    responses={
        200: {"description": "OCR text + analysis result"},
        422: {"description": "Invalid image, unsupported format, or no text found"},
        429: {"description": "Rate limit exceeded"},
        503: {"description": "EasyOCR service unavailable"},
    },
)
@limiter.limit("10/minute")
async def analyze_image(
    request: Request,
    file: UploadFile = File(..., description="Image or PDF file to scan for scam text"),
) -> ImageAnalysisResponse:
    """
    Analyse an image for scam content.

    **Pipeline:**
    1. Validate format and file size
    2. Write to secure temp file
    3. Run EasyOCR to extract text
    4. Delete temp file
    5. Analyse extracted text with full AI engine pipeline
    6. Return extracted text + analysis
    """
    settings = get_settings()

    if not ocr_service.available:
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "error": "OCR Service Unavailable",
                "detail": "EasyOCR is not installed. Install with: pip install easyocr",
            },
        )

    # Read file bytes
    image_bytes = await file.read()

    # Validate
    try:
        validate_image_file(
            filename=file.filename or "image.tmp",
            content_type=file.content_type or "",
            size_bytes=len(image_bytes),
            max_bytes=settings.max_image_bytes,
        )
    except ValueError as exc:
        raise OCRError(str(exc), filename=file.filename)

    logger.info(
        "Image analysis request",
        extra={
            "filename": file.filename,
            "content_type": file.content_type,
            "size_bytes": len(image_bytes),
        },
    )

    # Extract text → analyse
    async with temp_image_file(image_bytes, file.filename or "image.tmp") as image_path:
        extracted_text, ocr_confidence = await ocr_service.extract_text(image_path)

    logger.info(
        "OCR complete",
        extra={
            "chars": len(extracted_text),
            "confidence": round(ocr_confidence, 3),
            "preview": extracted_text[:60],
        },
    )

    analysis = await ai_engine.analyze(extracted_text)

    return ImageAnalysisResponse(
        extracted_text=extracted_text,
        analysis=analysis,
        ocr_confidence=round(ocr_confidence, 3),
    )
