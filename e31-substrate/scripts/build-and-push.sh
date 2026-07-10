#!/usr/bin/env bash
# Build, push, and capture digests for all E31 substrate service images.
set -euo pipefail

REGISTRY="${REGISTRY:-e31.local:5000}"
TAG="${TAG:-v1}"
PLATFORM="${PLATFORM:-linux/arm64}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES_FILE="$(cd "${ROOT}/../charts/e31-substrate" && pwd)/values.yaml"

SERVICES=(
  memory
  retrieval
  inference
  fine-tuning
  eval
  watchman
  local-bridge
)

declare -A KEY_MAP=(
  [memory]=memory
  [retrieval]=retrieval
  [inference]=inference
  [fine-tuning]=fineTuning
  [eval]=eval
  [watchman]=watchman
  [local-bridge]=localBridge
)

echo "Building and pushing ${#SERVICES[@]} service images to ${REGISTRY}..."

for service in "${SERVICES[@]}"; do
  image="${REGISTRY}/${service}:${TAG}"
  context="${ROOT}/${service}/docker"

  echo "==> Building ${image}"
  docker buildx build \
    --platform "${PLATFORM}" \
    -t "${image}" \
    --load \
    "${context}"

  echo "==> Pushing ${image}"
  docker push "${image}"

  digest=$(docker inspect --format='{{index .RepoDigests 0}}' "${image}")
  echo "    Digest: ${digest}"
done

echo ""
echo "Updating digests in ${VALUES_FILE}..."
python3 - "${VALUES_FILE}" "${REGISTRY}" "${TAG}" <<'PY'
import re
import subprocess
import sys

values_path, registry, tag = sys.argv[1:4]

services = [
    ("memory", "memory"),
    ("retrieval", "retrieval"),
    ("inference", "inference"),
    ("fine-tuning", "fineTuning"),
    ("eval", "eval"),
    ("watchman", "watchman"),
    ("local-bridge", "localBridge"),
]

with open(values_path) as f:
    content = f.read()

for svc, key in services:
    image = f"{registry}/{svc}:{tag}"
    result = subprocess.run(
        ["docker", "inspect", "--format={{index .RepoDigests 0}}", image],
        capture_output=True,
        text=True,
        check=True,
    )
    full = result.stdout.strip()
    sha = full.split("@sha256:")[1] if "@sha256:" in full else ""
    pattern = rf"({key}:\n(?:  .+\n)*?  image:\n(?:    .+\n)*?    digest: )\".*\""
    content = re.sub(pattern, rf'\1"sha256:{sha}"', content)
    print(f"  {svc}: sha256:{sha}")

with open(values_path, "w") as f:
    f.write(content)
PY

echo "Done."
