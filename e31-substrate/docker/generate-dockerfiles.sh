#!/usr/bin/env bash
# Generate per-service Dockerfiles from Dockerfile.template.
# Each generated Dockerfile pins the JetPack 7.2 base digest (LABEL + ARG)
# and sets service-specific defaults.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_ENV="${DOCKER_DIR}/services.env"
BASE_DIGEST_FILE="${DOCKER_DIR}/.jetpack-digest"

BASE_DIGEST="${BASE_DIGEST:-}"
if [[ -z "${BASE_DIGEST}" && -f "${BASE_DIGEST_FILE}" ]]; then
  BASE_DIGEST="$(tr -d '[:space:]' < "${BASE_DIGEST_FILE}")"
fi
if [[ -z "${BASE_DIGEST}" ]]; then
  BASE_DIGEST="sha256:0000000000000000000000000000000000000000000000000000000000000000"
  echo "WARN: No JetPack digest set; using placeholder. Build base first." >&2
fi

# Tag form works for local daemon builds; override with image@digest for registry.
BASE_IMAGE="${BASE_IMAGE:-e31.local:5000/jetpack:7.2}"

while IFS='|' read -r name module port context || [[ -n "${name:-}" ]]; do
  [[ -z "${name}" || "${name}" =~ ^# ]] && continue
  out="${ROOT}/${context}/Dockerfile"
  mkdir -p "$(dirname "${out}")"

  cat > "${out}" <<EOF
# syntax=docker/dockerfile:1.7
# Auto-generated from e31-substrate/docker/Dockerfile.template — do not edit by hand.
# Regenerate: ./e31-substrate/docker/generate-dockerfiles.sh
#
# Service: ${name}
# Module:  ${module}
# Port:    ${port}
# JetPack 7.2 base digest (pinned): ${BASE_DIGEST}

ARG BASE_IMAGE=${BASE_IMAGE}
ARG BASE_DIGEST=${BASE_DIGEST}

ARG SERVICE_NAME=${name}
ARG SERVICE_MODULE=${module}
ARG SERVICE_PORT=${port}

# ---------------------------------------------------------------------------
# Stage 1: builder
# ---------------------------------------------------------------------------
FROM \${BASE_IMAGE} AS builder

ARG SERVICE_NAME
WORKDIR /build

COPY requirements.txt .
COPY requirements*.txt ./

RUN python3 -m venv /opt/venv \\
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \\
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt \\
    && if [ -f requirements-qdrant.txt ]; then \\
         /opt/venv/bin/pip install --no-cache-dir -r requirements-qdrant.txt || true; \\
       fi \\
    && find /opt/venv -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true \\
    && find /opt/venv -type f -name '*.pyc' -delete 2>/dev/null || true

COPY src/ /build/src/

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM \${BASE_IMAGE} AS runtime

ARG SERVICE_NAME
ARG SERVICE_MODULE
ARG SERVICE_PORT
ARG BASE_DIGEST

LABEL org.opencontainers.image.title="E31 \${SERVICE_NAME}" \\
      org.opencontainers.image.description="E31 substrate \${SERVICE_NAME} service" \\
      e31.service.name="\${SERVICE_NAME}" \\
      e31.jetpack.version="7.2" \\
      e31.base.digest="\${BASE_DIGEST}"

ENV SERVICE_NAME=\${SERVICE_NAME} \\
    SERVICE_MODULE=\${SERVICE_MODULE} \\
    PORT=\${SERVICE_PORT} \\
    PATH="/opt/venv/bin:\${PATH}" \\
    NVIDIA_VISIBLE_DEVICES=all \\
    VIRTUAL_ENV=/opt/venv

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /build/src/ ./

EXPOSE \${SERVICE_PORT}

RUN groupadd --system --gid 10001 e31 \\
    && useradd --system --uid 10001 --gid e31 --home-dir /app --shell /usr/sbin/nologin e31 \\
    && chown -R e31:e31 /app

USER e31

ENTRYPOINT ["tini", "--"]
CMD ["sh", "-c", "exec python -m \${SERVICE_MODULE}"]
EOF

  echo "Wrote ${out}"
done < "${SERVICES_ENV}"

echo "Done. BASE_DIGEST=${BASE_DIGEST} BASE_IMAGE=${BASE_IMAGE}"
