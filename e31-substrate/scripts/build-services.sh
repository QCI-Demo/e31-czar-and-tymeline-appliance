#!/usr/bin/env bash
# Build JetPack 7.2 base + all seven E31 substrate service images (linux/arm64).
# Signs images with Cosign and generates Syft SBOMs when keys/tools are available.
set -euo pipefail

REGISTRY="${REGISTRY:-e31.local:5000}"
TAG="${TAG:-v1}"
PLATFORM="${PLATFORM:-linux/arm64}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_DIR="${ROOT}/docker"
COSIGN_KEY="${COSIGN_KEY:-}"
PUSH="${PUSH:-0}"
SIGN="${SIGN:-1}"
SBOM="${SBOM:-1}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${ROOT}/../dist/artifacts}"

SERVICES_ENV="${DOCKER_DIR}/services.env"

mkdir -p "${ARTIFACT_DIR}/sboms" "${ARTIFACT_DIR}/signatures"

echo "==> Building JetPack 7.2 base image"
sudo docker buildx create --name e31builder --use 2>/dev/null || sudo docker buildx use e31builder 2>/dev/null || true
sudo docker buildx build \
  --platform "${PLATFORM}" \
  -f "${DOCKER_DIR}/Dockerfile.base" \
  -t "${REGISTRY}/jetpack:7.2" \
  --load \
  "${DOCKER_DIR}"

# Capture and pin digest
BASE_DIGEST="$(sudo docker inspect --format='{{index .RepoDigests 0}}' "${REGISTRY}/jetpack:7.2" 2>/dev/null || true)"
if [[ -z "${BASE_DIGEST}" || "${BASE_DIGEST}" == "<no value>" ]]; then
  # Image may not have a repo digest until pushed; compute image ID hash fallback
  IMG_ID="$(sudo docker inspect --format='{{.Id}}' "${REGISTRY}/jetpack:7.2")"
  BASE_DIGEST="sha256:${IMG_ID#sha256:}"
else
  BASE_DIGEST="sha256:${BASE_DIGEST#*@sha256:}"
fi
echo "${BASE_DIGEST}" | tee "${DOCKER_DIR}/.jetpack-digest"
echo "    JetPack 7.2 digest: ${BASE_DIGEST}"

# Generate per-service Dockerfiles with pinned digest metadata
BASE_DIGEST="${BASE_DIGEST}" BASE_IMAGE="${REGISTRY}/jetpack:7.2" \
  bash "${DOCKER_DIR}/generate-dockerfiles.sh"

echo "==> Building substrate services"
while IFS='|' read -r name module port context || [[ -n "${name:-}" ]]; do
  [[ -z "${name}" || "${name}" =~ ^# ]] && continue
  image="${REGISTRY}/${name}:${TAG}"
  ctx="${ROOT}/${context}"
  echo "---- Building ${image} (module=${module} port=${port})"
  # Verify base digest still matches pin before build
  CURRENT="$(sudo docker inspect --format='{{.Id}}' "${REGISTRY}/jetpack:7.2")"
  CURRENT="sha256:${CURRENT#sha256:}"
  if [[ "${CURRENT}" != "${BASE_DIGEST}" ]]; then
    echo "ERROR: JetPack digest drift: expected ${BASE_DIGEST}, got ${CURRENT}" >&2
    exit 1
  fi
  sudo docker buildx build \
    --platform "${PLATFORM}" \
    --pull=false \
    --build-arg "BASE_IMAGE=${REGISTRY}/jetpack:7.2" \
    --build-arg "BASE_DIGEST=${BASE_DIGEST}" \
    --build-arg "SERVICE_NAME=${name}" \
    --build-arg "SERVICE_MODULE=${module}" \
    --build-arg "SERVICE_PORT=${port}" \
    -f "${ctx}/Dockerfile" \
    -t "${image}" \
    --load \
    "${ctx}"

  if [[ "${PUSH}" == "1" ]]; then
    sudo docker push "${image}"
  fi

  if [[ "${SBOM}" == "1" ]] && command -v syft >/dev/null; then
    echo "    Generating SBOM for ${image}"
    syft "docker:${image}" -o json > "${ARTIFACT_DIR}/sboms/sbom-${name}.json"
  fi

  if [[ "${SIGN}" == "1" && -n "${COSIGN_KEY}" ]] && command -v cosign >/dev/null; then
    echo "    Signing ${image}"
    cosign sign --yes --key "${COSIGN_KEY}" "${image}" \
      || cosign sign --yes --key "${COSIGN_KEY}" --tlog-upload=false "${image}"
    # Also export a detached signature artifact for air-gap
    cosign save --dir "${ARTIFACT_DIR}/signatures/${name}" "${image}" 2>/dev/null || true
  fi
done < "${SERVICES_ENV}"

echo "==> Build complete. Artifacts in ${ARTIFACT_DIR}"
