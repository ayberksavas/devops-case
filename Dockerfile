# syntax=docker/dockerfile:1.7

# ---- Stage 1: builder ----
# Install Python deps into an isolated virtualenv so the runtime stage
# can copy a self-contained tree without pulling in pip/setuptools metadata.
FROM python:3.12-slim AS builder

WORKDIR /build

COPY requirements.txt .

RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt


# ---- Stage 2: runtime ----
FROM python:3.12-slim

# Non-root user with no login shell. UID 1000 matches common host UIDs.
RUN useradd --create-home --uid 1000 --shell /usr/sbin/nologin appuser

# Copy the venv from the builder stage, owned by the non-root user.
COPY --from=builder --chown=appuser:appuser /opt/venv /opt/venv

WORKDIR /app
COPY --chown=appuser:appuser app.py gunicorn.conf.py ./

# prometheus_client multiprocess mode writes per-worker mmap files here. The
# dir is created in the image for local `docker run`; in Kubernetes an emptyDir
# volume is mounted on top of it (see Helm chart values).
RUN mkdir -p /tmp/prometheus_multiproc \
 && chown appuser:appuser /tmp/prometheus_multiproc

USER appuser

ENV PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8080 \
    PROMETHEUS_MULTIPROC_DIR=/tmp/prometheus_multiproc

EXPOSE 8080

# Uses Python stdlib (no curl/wget needed in the image).
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status == 200 else 1)"

ENTRYPOINT ["gunicorn", "-c", "gunicorn.conf.py", "app:app"]
