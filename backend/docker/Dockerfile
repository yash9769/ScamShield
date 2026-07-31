# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

# System deps for EasyOCR, Whisper, pdf2image
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxrender1 \
    libxext6 \
    ffmpeg \
    poppler-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Install Python dependencies into a venv for clean copying
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

LABEL maintainer="ScamShield Team"
LABEL description="ScamShield AI Backend — Production Image"
LABEL version="2.0.0"

# Minimal runtime system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-glx \
    libglib2.0-0 \
    ffmpeg \
    poppler-utils \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy venv from builder stage
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Create non-root user for security
RUN groupadd -r scamshield && \
    useradd -r -g scamshield -d /app -s /sbin/nologin scamshield

WORKDIR /app

# Copy application code
COPY --chown=scamshield:scamshield app/ ./app/

# Create temp directory for audio/image processing
RUN mkdir -p /tmp/scamshield && chown scamshield:scamshield /tmp/scamshield

# Switch to non-root user
USER scamshield

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Start server
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--workers", "2", \
     "--log-level", "info", \
     "--access-log"]
