# ── Stage 1: Builder ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

# System deps for Python packages and tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxrender1 \
    libxext6 \
    ffmpeg \
    poppler-utils \
    yara \
    default-jre-headless \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Install Python dependencies into a venv for clean copying
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Download apktool
RUN curl -L -o /opt/apktool https://raw.githubusercontent.com/iBotPeaches/Apktool/master/scripts/linux/apktool && \
    chmod +x /opt/apktool && \
    curl -L -o /opt/apktool.jar https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_2.9.3.jar

# Download JADX
RUN curl -L -o /opt/jadx.zip https://github.com/skylot/jadx/releases/download/v1.4.7/jadx-1.4.7.zip && \
    unzip /opt/jadx.zip -d /opt/jadx && \
    chmod +x /opt/jadx/bin/jadx && \
    rm /opt/jadx.zip

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

LABEL maintainer="ScamShield Team"
LABEL description="ScamShield AI Backend — Production Image"
LABEL version="2.0.0"

# Minimal runtime system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    ffmpeg \
    poppler-utils \
    curl \
    yara \
    default-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# Copy venv from builder stage
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy tools from builder
COPY --from=builder /opt/apktool /usr/local/bin/apktool
COPY --from=builder /opt/apktool.jar /usr/local/bin/apktool.jar
COPY --from=builder /opt/jadx /opt/jadx

RUN ln -s /opt/jadx/bin/jadx /usr/local/bin/jadx

# Create non-root user for security
RUN groupadd -r scamshield && \
    useradd -r -g scamshield -d /app -s /sbin/nologin scamshield

WORKDIR /app

# Copy application code
COPY --chown=scamshield:scamshield app/ ./app/
COPY --chown=scamshield:scamshield yara_rules/ ./yara_rules/

# Create necessary directories
RUN mkdir -p /tmp/scamshield /app/uploads /app/reports /app/.local && \
    chown -R scamshield:scamshield /tmp/scamshield /app/uploads /app/reports /app/.local

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
