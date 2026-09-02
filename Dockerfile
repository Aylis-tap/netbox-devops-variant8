# ==========================================
# Multi-Stage Dockerfile for NetBox (Variant 8)
# Stage 1: Build & Dependencies compilation
# ==========================================
FROM python:3.11-slim-bookworm AS builder

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /opt/netbox

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    libxml2-dev \
    libxslt1-dev \
    libffi-dev \
    libssl-dev \
    zlib1g-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

COPY netbox-src/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt gunicorn prometheus-client django-prometheus

# ==========================================
# Stage 2: Minimal Runtime Environment
# ==========================================
FROM python:3.11-slim-bookworm AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/usr/local/bin:$PATH" \
    PYTHONPATH="/opt/netbox/netbox"

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    libxml2 \
    libxslt1.1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Non-root user creation (Requirement P1/Stage 1)
RUN groupadd -g 1000 netbox && \
    useradd -u 1000 -g netbox -d /opt/netbox -s /bin/sh netbox

WORKDIR /opt/netbox

# Copy installed wheels and binaries from builder
COPY --from=builder /install /usr/local
COPY --chown=netbox:netbox netbox-src/ /opt/netbox/

# Configure directory permissions for static & media files
RUN mkdir -p /opt/netbox/netbox/static /opt/netbox/netbox/media && \
    chown -R netbox:netbox /opt/netbox

USER netbox

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=5s --retries=6 --start-period=30s \
    CMD curl -f http://localhost:8000/api/status/ || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "3", "--threads", "2", "--timeout", "120", "netbox.wsgi"]
