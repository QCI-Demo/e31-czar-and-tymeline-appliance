# syntax=docker/dockerfile:1.7
# Auto-generated from e31-substrate/docker/Dockerfile.template — do not edit by hand.
# Regenerate: ./e31-substrate/docker/generate-dockerfiles.sh
#
# Service: memory
# Module:  memory.main
# Port:    8080
# JetPack 7.2 base digest (pinned): sha256:904878f08fb0fca5489096d9dc9ed16c64a0f63f0a48e211fddc4ce830df83bd

ARG BASE_IMAGE=e31.local:5000/jetpack:7.2
ARG BASE_DIGEST=sha256:904878f08fb0fca5489096d9dc9ed16c64a0f63f0a48e211fddc4ce830df83bd

ARG SERVICE_NAME=memory
ARG SERVICE_MODULE=memory.main
ARG SERVICE_PORT=8080

# ---------------------------------------------------------------------------
# Stage 1: builder
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS builder

ARG SERVICE_NAME
WORKDIR /build

COPY requirements.txt .
COPY requirements*.txt ./

RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt \
    && if [ -f requirements-qdrant.txt ]; then \
         /opt/venv/bin/pip install --no-cache-dir -r requirements-qdrant.txt || true; \
       fi \
    && find /opt/venv -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true \
    && find /opt/venv -type f -name '*.pyc' -delete 2>/dev/null || true

COPY src/ /build/src/

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS runtime

ARG SERVICE_NAME
ARG SERVICE_MODULE
ARG SERVICE_PORT
ARG BASE_DIGEST

LABEL org.opencontainers.image.title="E31 ${SERVICE_NAME}" \
      org.opencontainers.image.description="E31 substrate ${SERVICE_NAME} service" \
      e31.service.name="${SERVICE_NAME}" \
      e31.jetpack.version="7.2" \
      e31.base.digest="${BASE_DIGEST}"

ENV SERVICE_NAME=${SERVICE_NAME} \
    SERVICE_MODULE=${SERVICE_MODULE} \
    PORT=${SERVICE_PORT} \
    PATH="/opt/venv/bin:${PATH}" \
    NVIDIA_VISIBLE_DEVICES=all \
    VIRTUAL_ENV=/opt/venv

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /build/src/ ./

EXPOSE ${SERVICE_PORT}

RUN groupadd --system --gid 10001 e31 \
    && useradd --system --uid 10001 --gid e31 --home-dir /app --shell /usr/sbin/nologin e31 \
    && chown -R e31:e31 /app

USER e31

ENTRYPOINT ["tini", "--"]
CMD ["sh", "-c", "exec python -m ${SERVICE_MODULE}"]
