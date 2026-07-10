# E31 Substrate Services

Containerized substrate services for k3s deployment on Jetson AGX Thor.

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

## Runtime

- Base image: `nvcr.io/nvidia/l4t-base:r35.2.1` (Jetson-compatible)
- Python 3.12 via python-build-standalone (L4T r35 / Ubuntu 20.04 has no python3.12 apt package on arm64)
- `NVIDIA_VISIBLE_DEVICES=all` on every service for GPU runtime
- Retrieval sets `VECTOR_STORE_PATH=/data/vectors` and installs `qdrant-client`

## Building Images

Each service Dockerfile lives under `e31-substrate/<service>/docker/`. Build from the docker directory:

```bash
cd e31-substrate/<service>/docker
docker build --platform linux/arm64 -t e31.local:5000/<service>:v1 .
docker push e31.local:5000/<service>:v1
docker inspect --format='{{index .RepoDigests 0}}' e31.local:5000/<service>:v1
```

Or build all services at once (updates Helm digests):

```bash
./e31-substrate/scripts/build-and-push.sh
```

## Helm Deployment

Image digests are pinned in `charts/e31-substrate/values.yaml` for reproducible deployments.

```bash
helm install e31-substrate charts/e31-substrate -n e31-substrate --create-namespace
```

All containers request `nvidia.com/gpu: 1` and use the NVIDIA container runtime on Jetson AGX Thor.
