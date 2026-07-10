#!/usr/bin/env bash
# Assemble a content-addressed OCI release bundle for air-gap provisioning.
#
# Aggregates:
#   - signed substrate service images (via skopeo)
#   - model weight directories
#   - Helm charts
#   - uv.lock files
#   - runbooks
#
# Produces:
#   - e31-release-<version>.tar (permissions preserved)
#   - manifest.sha256 (content-addressed inventory)
#   - manifest.sha256.sig (Cosign signature over the manifest)
#
# Usage:
#   ./assemble-release-bundle.sh [--registry REG] [--tag TAG] [--out DIR] [--version VER]
set -euo pipefail

REGISTRY="${REGISTRY:-e31.local:5000}"
TAG="${TAG:-v1}"
VERSION="${VERSION:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_DIR="${OUT_DIR:-./dist/release-bundle}"
COSIGN_KEY="${COSIGN_KEY:-}"
RELEASE_BUNDLE_REPO="${RELEASE_BUNDLE_REPO:-}"
SKIP_CLONE="${SKIP_CLONE:-0}"
PLATFORM="${PLATFORM:-linux/arm64}"

SERVICES=(memory retrieval inference fine-tuning eval watchman local-bridge)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]
  --registry REG     Image registry (default: ${REGISTRY})
  --tag TAG          Image tag (default: ${TAG})
  --version VER      Bundle version string (default: UTC timestamp)
  --out DIR          Output directory (default: ${OUT_DIR})
  --cosign-key PATH  Cosign private key for manifest signing
  --release-repo URL Optional release-bundle repo to clone/merge
  --skip-clone       Do not clone release-bundle repo
  -h, --help         Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --cosign-key) COSIGN_KEY="$2"; shift 2 ;;
    --release-repo) RELEASE_BUNDLE_REPO="$2"; shift 2 ;;
    --skip-clone) SKIP_CLONE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

OUT_DIR="$(mkdir -p "${OUT_DIR}" && cd "${OUT_DIR}" && pwd)"
BUNDLE_ROOT="${OUT_DIR}/bundle"
IMAGES_DIR="${BUNDLE_ROOT}/images"
MODELS_DIR="${BUNDLE_ROOT}/models"
CHARTS_DIR="${BUNDLE_ROOT}/charts"
LOCKFILES_DIR="${BUNDLE_ROOT}/lockfiles"
RUNBOOKS_DIR="${BUNDLE_ROOT}/runbooks"
META_DIR="${BUNDLE_ROOT}/meta"

echo "==> Assembling E31 OCI release bundle version=${VERSION}"
rm -rf "${BUNDLE_ROOT}"
mkdir -p "${IMAGES_DIR}" "${MODELS_DIR}" "${CHARTS_DIR}" "${LOCKFILES_DIR}" "${RUNBOOKS_DIR}" "${META_DIR}"

# 1) Optionally clone the release-bundle repo for shared assets
if [[ "${SKIP_CLONE}" != "1" && -n "${RELEASE_BUNDLE_REPO}" ]]; then
  CLONE_DIR="${OUT_DIR}/release-bundle-src"
  echo "==> Cloning release-bundle repo: ${RELEASE_BUNDLE_REPO}"
  rm -rf "${CLONE_DIR}"
  git clone --depth 1 "${RELEASE_BUNDLE_REPO}" "${CLONE_DIR}"
  # Merge known asset trees if present
  for d in models charts runbooks lockfiles; do
    if [[ -d "${CLONE_DIR}/${d}" ]]; then
      cp -a "${CLONE_DIR}/${d}/." "${BUNDLE_ROOT}/${d}/"
    fi
  done
elif [[ -d "${ROOT}/release-bundle" ]]; then
  echo "==> Using local release-bundle/ assets"
  for d in models charts runbooks lockfiles; do
    if [[ -d "${ROOT}/release-bundle/${d}" ]]; then
      cp -a "${ROOT}/release-bundle/${d}/." "${BUNDLE_ROOT}/${d}/"
    fi
  done
fi

# 2) Fetch signed images with skopeo into a local OCI directory layout
echo "==> Fetching images via skopeo"
DIGESTS_FILE="${META_DIR}/image-digests.sha256"
: > "${DIGESTS_FILE}"

for service in "${SERVICES[@]}"; do
  src="docker://${REGISTRY}/${service}:${TAG}"
  dest_dir="${IMAGES_DIR}/${service}"
  mkdir -p "${dest_dir}"
  echo "    skopeo copy ${src} -> oci:${dest_dir}:${TAG}"
  if ! skopeo copy --override-arch arm64 --override-os linux \
      "${src}" "oci:${dest_dir}:${TAG}" 2>/tmp/skopeo-${service}.err; then
    # Fallback: try local docker daemon
    echo "    skopeo remote failed; trying docker-daemon:${REGISTRY}/${service}:${TAG}"
    skopeo copy --override-arch arm64 --override-os linux \
      "docker-daemon:${REGISTRY}/${service}:${TAG}" "oci:${dest_dir}:${TAG}"
  fi
  # Record content digest of the OCI layout index/manifest
  if command -v sha256sum >/dev/null; then
    # Hash the oci-layout + index.json + blobs for a stable content address
    (
      cd "${dest_dir}"
      find . -type f | LC_ALL=C sort | xargs sha256sum
    ) > "${META_DIR}/${service}.files.sha256"
    img_digest="$(sha256sum "${META_DIR}/${service}.files.sha256" | awk '{print $1}')"
  else
    img_digest="unknown"
  fi
  echo "sha256:${img_digest}  ${service}:${TAG}" >> "${DIGESTS_FILE}"
  echo "    ${service} content digest: sha256:${img_digest}"
done

# Also include JetPack base if present
if skopeo inspect "docker-daemon:${REGISTRY}/jetpack:7.2" >/dev/null 2>&1 \
   || skopeo inspect "docker://${REGISTRY}/jetpack:7.2" >/dev/null 2>&1; then
  dest_dir="${IMAGES_DIR}/jetpack"
  mkdir -p "${dest_dir}"
  if ! skopeo copy --override-arch arm64 --override-os linux \
      "docker://${REGISTRY}/jetpack:7.2" "oci:${dest_dir}:7.2" 2>/dev/null; then
    skopeo copy --override-arch arm64 --override-os linux \
      "docker-daemon:${REGISTRY}/jetpack:7.2" "oci:${dest_dir}:7.2"
  fi
fi

# 3) Aggregate model weights, Helm charts, lockfiles, runbooks from repo
echo "==> Aggregating model weights, charts, lockfiles, runbooks"
if [[ -d "${ROOT}/models" ]]; then
  cp -a "${ROOT}/models/." "${MODELS_DIR}/"
fi
if [[ -d "${ROOT}/charts" ]]; then
  cp -a "${ROOT}/charts/." "${CHARTS_DIR}/"
fi
# Collect uv.lock files (exclude build/dist/git trees)
while IFS= read -r -d '' lock; do
  rel="${lock#${ROOT}/}"
  dest="${LOCKFILES_DIR}/${rel}"
  mkdir -p "$(dirname "${dest}")"
  cp -a "${lock}" "${dest}"
done < <(find "${ROOT}" \
  \( -path "${ROOT}/dist" -o -path "${ROOT}/.git" -o -path "${ROOT}/release-bundle" \) -prune -o \
  -name 'uv.lock' -type f -print0 2>/dev/null || true)

if [[ -d "${ROOT}/docs/runbooks" ]]; then
  cp -a "${ROOT}/docs/runbooks/." "${RUNBOOKS_DIR}/"
fi

# Bundle metadata (deterministic created_at from SOURCE_DATE_EPOCH)
CREATED_AT="$(date -u -d "@${SOURCE_DATE_EPOCH}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -r "${SOURCE_DATE_EPOCH}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || printf '%s' "${SOURCE_DATE_EPOCH}")"
cat > "${META_DIR}/bundle.json" <<EOF
{
  "name": "e31-substrate-release",
  "version": "${VERSION}",
  "registry": "${REGISTRY}",
  "tag": "${TAG}",
  "platform": "${PLATFORM}",
  "services": $(printf '%s\n' "${SERVICES[@]}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'),
  "created_at": "${CREATED_AT}",
  "source_date_epoch": "${SOURCE_DATE_EPOCH}"
}
EOF

# 4) Tar the directory preserving file permissions
TAR_NAME="e31-release-${VERSION}.tar"
TAR_PATH="${OUT_DIR}/${TAR_NAME}"
echo "==> Creating OCI tar archive: ${TAR_PATH}"
# Deterministic tar: sorted names, stable owner, clamped mtime, no atime/ctime pax headers
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "${ROOT}" log -1 --format=%ct 2>/dev/null || date +%s)}"
(
  cd "${OUT_DIR}"
  find bundle -exec touch -d "@${SOURCE_DATE_EPOCH}" {} + 2>/dev/null \
    || find bundle -exec touch -t "$(date -u -d "@${SOURCE_DATE_EPOCH}" +%Y%m%d%H%M.%S)" {} +
  tar --sort=name \
      --owner=0 --group=0 --numeric-owner \
      --mtime="@${SOURCE_DATE_EPOCH}" \
      --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
      --format=posix \
      -cf "${TAR_NAME}" bundle
)

# 5) Generate SHA256 manifest and sign with Cosign
MANIFEST="${OUT_DIR}/manifest.sha256"
echo "==> Generating SHA256 manifest: ${MANIFEST}"
(
  cd "${OUT_DIR}"
  # Hash the tar and every file under bundle/ for content addressing
  sha256sum "${TAR_NAME}" > manifest.sha256
  (
    cd bundle
    find . -type f | LC_ALL=C sort | xargs sha256sum
  ) >> manifest.sha256
)

TAR_SHA="$(awk 'NR==1{print $1}' "${MANIFEST}")"
echo "${TAR_SHA}" > "${OUT_DIR}/bundle.sha256"
echo "==> Bundle archive sha256: ${TAR_SHA}"

if [[ -n "${COSIGN_KEY}" ]]; then
  echo "==> Signing manifest with Cosign key ${COSIGN_KEY}"
  # Sign the blob (manifest file) — produces .sig
  cosign sign-blob --yes --key "${COSIGN_KEY}" \
    --output-signature "${MANIFEST}.sig" \
    --output-certificate "${MANIFEST}.crt" \
    "${MANIFEST}" 2>/dev/null || cosign sign-blob --yes --key "${COSIGN_KEY}" \
    --output-signature "${MANIFEST}.sig" \
    "${MANIFEST}"
  echo "    Wrote ${MANIFEST}.sig"
elif [[ -n "${COSIGN_PRIVATE_KEY:-}" ]]; then
  echo "==> Signing manifest with COSIGN_PRIVATE_KEY env"
  KEY_FILE="$(mktemp)"
  printf '%s\n' "${COSIGN_PRIVATE_KEY}" > "${KEY_FILE}"
  chmod 600 "${KEY_FILE}"
  cosign sign-blob --yes --key "${KEY_FILE}" \
    --output-signature "${MANIFEST}.sig" \
    "${MANIFEST}"
  rm -f "${KEY_FILE}"
else
  echo "WARN: No Cosign key provided; writing unsigned placeholder signature" >&2
  sha256sum "${MANIFEST}" | awk '{print $1}' > "${MANIFEST}.sig"
fi

# Publish pointer for CI
cat > "${OUT_DIR}/bundle-info.json" <<EOF
{
  "tar": "${TAR_NAME}",
  "tar_sha256": "${TAR_SHA}",
  "manifest": "manifest.sha256",
  "version": "${VERSION}",
  "source_date_epoch": "${SOURCE_DATE_EPOCH}"
}
EOF

echo "==> Bundle assembly complete: ${OUT_DIR}"
ls -la "${OUT_DIR}"
