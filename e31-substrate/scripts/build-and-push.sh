#!/usr/bin/env bash
# Build, push, and capture digests for all E31 substrate service images.
# Target: on-device local registry at e31.local:5000 (Jetson AGX Thor / k3s).
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

echo "Building and pushing ${#SERVICES[@]} service images to ${REGISTRY} (platform=${PLATFORM})..."

for service in "${SERVICES[@]}"; do
  image="${REGISTRY}/${service}:${TAG}"
  context="${ROOT}/${service}/docker"

  echo "==> Building ${image}"
  docker build \
    --platform "${PLATFORM}" \
    -t "${image}" \
    "${context}"

  echo "==> Pushing ${image}"
  docker push "${image}"

  digest=$(docker inspect --format='{{index .RepoDigests 0}}' "${image}")
  echo "    Digest: ${digest}"
done

echo ""
echo "Updating digests in ${VALUES_FILE}..."
python3 - "${VALUES_FILE}" "${REGISTRY}" "${TAG}" <<'PY'
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

try:
    import yaml
except ImportError:
    yaml = None

digests = {}
for svc, key in services:
    image = f"{registry}/{svc}:{tag}"
    result = subprocess.run(
        ["docker", "inspect", "--format={{index .RepoDigests 0}}", image],
        capture_output=True,
        text=True,
        check=True,
    )
    full = result.stdout.strip()
    sha = full.split("@", 1)[1] if "@" in full else full
    digests[key] = sha
    print(f"  {svc}: {sha}")

if yaml is not None:
    with open(values_path) as f:
        data = yaml.safe_load(f)
    for key, sha in digests.items():
        data[key]["image"]["digest"] = sha
    with open(values_path, "w") as f:
        yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
else:
    # Fallback: line-oriented replace under each service key block
    with open(values_path) as f:
        lines = f.readlines()
    current = None
    out = []
    for line in lines:
        if line.rstrip("\n") in {f"{k}:" for k in digests}:
            current = line.rstrip(":\n")
        if current and line.lstrip().startswith("digest:"):
            indent = line[: len(line) - len(line.lstrip())]
            out.append(f'{indent}digest: "{digests[current]}"\n')
            continue
        out.append(line)
    with open(values_path, "w") as f:
        f.writelines(out)
PY

echo "Done."
