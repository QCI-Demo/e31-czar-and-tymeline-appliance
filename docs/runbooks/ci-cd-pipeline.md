# E31 Substrate CI/CD Pipeline & Release Bundle

## Overview

This pipeline builds the JetPack 7.2 base image, containerizes all seven E31
substrate services, runs unit/integration tests, signs artifacts with Cosign,
generates Syft SBOMs, assembles a content-addressed OCI release bundle, and
verifies bit-for-bit reproducibility. The signed bundle is published to the
internal registry for air-gap provisioning of the sealed appliance.

## Workflow jobs

| Job | Purpose |
|-----|---------|
| `build` | Build JetPack 7.2 base + seven service images (linux/arm64) |
| `test` | Unit + integration tests |
| `sign` | Cosign-sign each image (`secrets.COSIGN_KEY`) |
| `sbom` | Syft SBOM (JSON + SPDX) per image |
| `bundle` | Assemble OCI tar + SHA256 manifest + Cosign-signed manifest |
| `verify` | Re-assemble on a clean runner; fail on digest mismatch |

Triggers: `push` to `main`, `pull_request` targeting `main`.

Concurrency: workflow-level group per ref; each job also sets a job-level
concurrency group. Artifact retention: **14 days**.

## Required secrets / vars

| Name | Type | Purpose |
|------|------|---------|
| `COSIGN_KEY` | secret | Cosign private key (PEM or base64) |
| `COSIGN_PASSWORD` | secret | Key password (if encrypted) |
| `E31_REGISTRY` | variable | Optional override (default `e31.local:5000`) |

If `COSIGN_KEY` is unset, CI generates an ephemeral keypair so the pipeline
still exercises signing (not for production trust).

## Local builds

```bash
# Build JetPack 7.2 base + all services (arm64)
./e31-substrate/scripts/build-services.sh

# Or use the template directly
docker buildx build --platform linux/arm64 \
  --build-arg SERVICE_NAME=memory \
  --build-arg SERVICE_MODULE=memory.main \
  --build-arg SERVICE_PORT=8080 \
  --build-arg BASE_DIGEST="$(cat e31-substrate/docker/.jetpack-digest)" \
  -f e31-substrate/docker/Dockerfile.template \
  -t e31.local:5000/memory:v1 \
  e31-substrate/memory/docker
```

## Release bundle format

```
e31-release-<version>.tar
└── bundle/
    ├── images/<service>/     # OCI layout via skopeo
    ├── models/               # model weight directories
    ├── charts/               # Helm charts
    ├── lockfiles/            # uv.lock files
    ├── runbooks/             # ops runbooks
    └── meta/
        ├── bundle.json
        └── image-digests.sha256
manifest.sha256               # content-addressed inventory
manifest.sha256.sig           # Cosign signature over manifest
bundle.sha256                 # archive checksum
bundle-info.json              # version + SOURCE_DATE_EPOCH
```

Assemble / verify:

```bash
./e31-substrate/scripts/assemble-release-bundle.sh --out dist/release-bundle
./e31-substrate/scripts/verify-reproducibility.sh \
  --reference dist/release-bundle --out dist/verify-bundle
```

## Air-gap provisioning

1. Transfer `e31-release-*.tar`, `manifest.sha256`, and `manifest.sha256.sig`
   to the sealed appliance via approved media.
2. Verify Cosign signature with the site trust root.
3. Extract and load images with skopeo/helm as described in
   `docs/runbooks/airgap-provisioning.md`.
