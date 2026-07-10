# E31 Czar & Tymeline Appliance

Sovereign, air-gap-capable AI appliance software stream (*E31 substrate*).

## Substrate services

Memory · Retrieval · Inference · Fine-Tuning · Eval · Watchman · Local Bridge

## CI/CD

Automated pipeline: `.github/workflows/ci.yml`

- Build JetPack 7.2 base + seven service images (linux/arm64)
- Unit & integration tests
- Cosign signing + Syft SBOMs
- Content-addressed OCI release bundle
- Reproducibility verification

See [docs/ci-cd/overview.md](docs/ci-cd/overview.md) (accreditation runbook) and
[docs/runbooks/ci-cd-pipeline.md](docs/runbooks/ci-cd-pipeline.md).

Internal portal: https://docs.internal.e31.local/ci-cd/overview

## Quick start

```bash
# Build base + services
./e31-substrate/scripts/build-services.sh

# Assemble air-gap release bundle
./e31-substrate/scripts/assemble-release-bundle.sh --out dist/release-bundle

# Verify reproducibility
./e31-substrate/scripts/verify-reproducibility.sh \
  --reference dist/release-bundle --out dist/verify-bundle
```
