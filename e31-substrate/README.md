# E31 Substrate Services

Containerized substrate services for k3s deployment on Jetson AGX Thor (JetPack 7.2).

## Services

| Service | Image | Port |
|---------|-------|------|
| Memory | `e31.local:5000/memory:v1` | 8080 |
| Retrieval | `e31.local:5000/retrieval:v1` | 8081 |
| Inference | `e31.local:5000/inference:v1` | 8082 |
| Fine-Tuning | `e31.local:5000/fine-tuning:v1` | 8083 |
| Eval | `e31.local:5000/eval:v1` | 8084 |
| Watchman | `e31.local:5000/watchman:v1` | 9090 |
| Local Bridge | `e31.local:5000/local-bridge:v1` | 8443 |

## Docker layout

- `e31-substrate/docker/Dockerfile.base` — JetPack 7.2 / Ubuntu 24.04 base
- `e31-substrate/docker/Dockerfile.template` — multi-stage service template (digest-pinned)
- `e31-substrate/docker/generate-dockerfiles.sh` — emit per-service Dockerfiles
- `e31-substrate/<service>/docker/` — service context (src, requirements)

## Building images

```bash
# Full build (base + all services, arm64), optional Cosign/Syft
./e31-substrate/scripts/build-services.sh

# Single service via template
BASE_DIGEST=$(cat e31-substrate/docker/.jetpack-digest)
docker buildx build --platform linux/arm64 \
  --build-arg BASE_DIGEST="${BASE_DIGEST}" \
  --build-arg SERVICE_NAME=memory \
  --build-arg SERVICE_MODULE=memory.main \
  --build-arg SERVICE_PORT=8080 \
  -f e31-substrate/docker/Dockerfile.template \
  -t e31.local:5000/memory:v1 \
  --load \
  e31-substrate/memory/docker
```

## Helm deployment

Image digests are pinned in `charts/e31-substrate/values.yaml`.

```bash
helm install e31-substrate charts/e31-substrate -n e31-substrate --create-namespace
```

## Tests

```bash
pip install pytest httpx fastapi uvicorn pydantic
export PYTHONPATH=e31-substrate/memory/docker/src:e31-substrate/retrieval/docker/src:e31-substrate/inference/docker/src:e31-substrate/fine-tuning/docker/src:e31-substrate/eval/docker/src:e31-substrate/watchman/docker/src:e31-substrate/local-bridge/docker/src
pytest e31-substrate/tests -v
```

## Release bundle

```bash
./e31-substrate/scripts/assemble-release-bundle.sh
./e31-substrate/scripts/verify-reproducibility.sh --reference dist/release-bundle
```
