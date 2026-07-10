#!/usr/bin/env bash
# Verify reproducibility of the E31 OCI release bundle.
#
# Re-runs bundle assembly on a clean workspace, recalculates image digests
# and the OCI archive checksum, and fails if any mismatch is detected against
# artifacts from a prior assembly job.
#
# Usage:
#   ./verify-reproducibility.sh --reference DIR [--out DIR]
set -euo pipefail

REFERENCE_DIR=""
OUT_DIR="${OUT_DIR:-./dist/verify-bundle}"
REGISTRY="${REGISTRY:-e31.local:5000}"
TAG="${TAG:-v1}"
VERSION="${VERSION:-}"
COSIGN_KEY="${COSIGN_KEY:-}"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ASSEMBLE="${ROOT}/e31-substrate/scripts/assemble-release-bundle.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") --reference DIR [options]
  --reference DIR    Directory with prior bundle artifacts (manifest.sha256, bundle.sha256)
  --out DIR          Clean output directory for re-assembly (default: ${OUT_DIR})
  --registry REG     Image registry
  --tag TAG          Image tag
  --version VER      Bundle version (must match reference for identical tar name)
  --cosign-key PATH  Cosign key (optional; signing compared separately)
  -h, --help         Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reference) REFERENCE_DIR="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --registry) REGISTRY="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --cosign-key) COSIGN_KEY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "${REFERENCE_DIR}" || ! -d "${REFERENCE_DIR}" ]]; then
  echo "ERROR: --reference DIR is required and must exist" >&2
  exit 1
fi

REF_BUNDLE_SHA="${REFERENCE_DIR}/bundle.sha256"
REF_MANIFEST="${REFERENCE_DIR}/manifest.sha256"
REF_INFO="${REFERENCE_DIR}/bundle-info.json"
REF_DIGESTS="${REFERENCE_DIR}/bundle/meta/image-digests.sha256"

if [[ ! -f "${REF_BUNDLE_SHA}" ]]; then
  echo "ERROR: missing ${REF_BUNDLE_SHA}" >&2
  exit 1
fi

# Recover version / SOURCE_DATE_EPOCH from reference for bit-for-bit match
if [[ -z "${VERSION}" && -f "${REF_INFO}" ]]; then
  VERSION="$(python3 -c "import json; print(json.load(open('${REF_INFO}'))['version'])")"
fi
if [[ -z "${SOURCE_DATE_EPOCH}" && -f "${REF_INFO}" ]]; then
  SOURCE_DATE_EPOCH="$(python3 -c "import json; print(json.load(open('${REF_INFO}')).get('source_date_epoch',''))" 2>/dev/null || true)"
fi
if [[ -z "${VERSION}" ]]; then
  VERSION="verify"
fi

echo "==> Reproducibility verification"
echo "    Reference: ${REFERENCE_DIR}"
echo "    Version:   ${VERSION}"
echo "    Epoch:     ${SOURCE_DATE_EPOCH:-unset}"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

export SOURCE_DATE_EPOCH REGISTRY TAG VERSION
ASSEMBLE_ARGS=(--registry "${REGISTRY}" --tag "${TAG}" --version "${VERSION}" --out "${OUT_DIR}" --skip-clone)
if [[ -n "${COSIGN_KEY}" ]]; then
  ASSEMBLE_ARGS+=(--cosign-key "${COSIGN_KEY}")
fi

echo "==> Re-running bundle assembly on clean output dir"
bash "${ASSEMBLE}" "${ASSEMBLE_ARGS[@]}"

NEW_BUNDLE_SHA_FILE="${OUT_DIR}/bundle.sha256"
NEW_MANIFEST="${OUT_DIR}/manifest.sha256"
NEW_DIGESTS="${OUT_DIR}/bundle/meta/image-digests.sha256"

MISMATCH=0

echo "==> Comparing bundle archive SHA256"
REF_SHA="$(tr -d '[:space:]' < "${REF_BUNDLE_SHA}")"
NEW_SHA="$(tr -d '[:space:]' < "${NEW_BUNDLE_SHA_FILE}")"
echo "    reference: ${REF_SHA}"
echo "    recomputed: ${NEW_SHA}"
if [[ "${REF_SHA}" != "${NEW_SHA}" ]]; then
  echo "FAIL: OCI archive checksum mismatch" >&2
  MISMATCH=1
else
  echo "OK: OCI archive checksum matches"
fi

echo "==> Comparing image digests"
if [[ -f "${REF_DIGESTS}" && -f "${NEW_DIGESTS}" ]]; then
  if ! diff -u "${REF_DIGESTS}" "${NEW_DIGESTS}"; then
    echo "FAIL: image digest inventory mismatch" >&2
    MISMATCH=1
  else
    echo "OK: image digests match"
  fi
else
  echo "WARN: image digest files missing; comparing full manifests instead" >&2
fi

echo "==> Comparing full SHA256 manifests (excluding signature lines)"
if [[ -f "${REF_MANIFEST}" && -f "${NEW_MANIFEST}" ]]; then
  # Compare sorted content hashes; first line is the tar hash already checked
  if ! diff -u <(tail -n +2 "${REF_MANIFEST}" | LC_ALL=C sort) \
              <(tail -n +2 "${NEW_MANIFEST}" | LC_ALL=C sort); then
    echo "FAIL: content manifest mismatch" >&2
    MISMATCH=1
  else
    echo "OK: content manifest matches"
  fi
else
  echo "WARN: manifest.sha256 missing in reference or new bundle" >&2
fi

if [[ "${MISMATCH}" -ne 0 ]]; then
  echo ""
  echo "REPRODUCIBILITY CHECK FAILED" >&2
  exit 1
fi

echo ""
echo "REPRODUCIBILITY CHECK PASSED"
exit 0
