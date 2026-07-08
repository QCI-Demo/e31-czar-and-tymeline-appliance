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

## Building Images

Each service Dockerfile lives under `e31-substrate/<service>/docker/`. Build from the docker directory:

```bash
cd e31-substrate/<service>/docker
docker build -t e31.local:5000/<service>:v1 .
docker push e31.local:5000/<service>:v1
docker inspect --format='{{index .RepoDigests 0}}' e31.local:5000/<service>:v1
```

Or build all services at once:

```bash
./e31-substrate/scripts/build-and-push.sh
```

For ARM64 cross-builds from x86 CI hosts, use docker buildx:

```bash
docker buildx build --platform linux/arm64 -t e31.local:5000/<service>:v1 --load .
```

## Helm Deployment

Image digests are pinned in `charts/e31-substrate/values.yaml` for reproducible deployments.

```bash
helm install e31-substrate charts/e31-substrate -n e31-substrate --create-namespace
```

All containers set `NVIDIA_VISIBLE_DEVICES=all` and request GPU resources for Jetson runtime.

## Retrieval Qdrant Client

The Retrieval service includes Qdrant client libraries via `requirements-qdrant.txt`. On native Jetson builds, install with:

```bash
pip3 install -r requirements-qdrant.txt
```

The base cross-build image includes the vector store path (`VECTOR_STORE_PATH=/data/vectors`) and installs Qdrant client libraries on-device where aarch64 grpcio wheels are available.
