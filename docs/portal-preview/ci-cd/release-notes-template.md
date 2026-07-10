# Release Notes Template — E31 Substrate Bundle

Copy this file to `docs/releases/e31-release-<version>.md` (or attach to the accreditation package) and replace all placeholders.

---

## E31 Substrate Release `<VERSION>`

| Field | Value |
|-------|-------|
| **Bundle version** | `<VERSION>` (12-char git SHA or semver) |
| **Git commit** | `<FULL_SHA>` |
| **Git tag** (if any) | `<TAG or n/a>` |
| **SOURCE_DATE_EPOCH** | `<unix-epoch>` |
| **Created at (UTC)** | `<YYYY-MM-DDTHH:MM:SSZ>` |
| **Platform** | `linux/arm64` |
| **Registry** | `e31.local:5000` |
| **CI workflow run** | `<URL>` |
| **Validation timestamp (UTC)** | `<YYYY-MM-DDTHH:MM:SSZ>` |
| **Validated by** | `<name / role>` |

### Summary

`<One paragraph: what changed in this release for the sealed appliance.>`

---

## Bundle checksum

| Artifact | Algorithm | Digest |
|----------|-----------|--------|
| `e31-release-<VERSION>.tar` | SHA-256 | `<bundle.sha256 contents>` |
| `manifest.sha256` | SHA-256 (of file) | `<sha256sum manifest.sha256>` |
| `manifest.sha256.sig` | Cosign sign-blob | Present: yes / no |
| Cosign public key fingerprint | SHA-256 | `<cosign.pub fingerprint>` |

Verify:

```bash
echo "<BUNDLE_SHA256>  e31-release-<VERSION>.tar" | sha256sum -c -
cosign verify-blob --key cosign.pub \
  --signature manifest.sha256.sig manifest.sha256
```

---

## Image digests

Populate from `bundle/meta/image-digests.sha256` and/or `docker inspect` / Cosign verify output.

| Service | Image reference | Content digest (`sha256:…`) | Cosign verified |
|---------|-----------------|-----------------------------|-----------------|
| JetPack base | `e31.local:5000/jetpack:7.2` | `<DIGEST>` | yes / n/a |
| Memory | `e31.local:5000/memory:v1` | `<DIGEST>` | yes / no |
| Retrieval | `e31.local:5000/retrieval:v1` | `<DIGEST>` | yes / no |
| Inference | `e31.local:5000/inference:v1` | `<DIGEST>` | yes / no |
| Fine-Tuning | `e31.local:5000/fine-tuning:v1` | `<DIGEST>` | yes / no |
| Eval | `e31.local:5000/eval:v1` | `<DIGEST>` | yes / no |
| Watchman | `e31.local:5000/watchman:v1` | `<DIGEST>` | yes / no |
| Local Bridge | `e31.local:5000/local-bridge:v1` | `<DIGEST>` | yes / no |

Ubuntu base pin used by JetPack Dockerfile:

| Base | Pin |
|------|-----|
| `ubuntu:24.04` | `sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90` |

---

## SBOM artifacts

| Service | Syft JSON | SPDX JSON | Generator |
|---------|-----------|-----------|-----------|
| Memory | `sbom-memory.json` | `sbom-memory.spdx.json` | Syft `<version>` |
| Retrieval | `sbom-retrieval.json` | `sbom-retrieval.spdx.json` | Syft `<version>` |
| Inference | `sbom-inference.json` | `sbom-inference.spdx.json` | Syft `<version>` |
| Fine-Tuning | `sbom-fine-tuning.json` | `sbom-fine-tuning.spdx.json` | Syft `<version>` |
| Eval | `sbom-eval.json` | `sbom-eval.spdx.json` | Syft `<version>` |
| Watchman | `sbom-watchman.json` | `sbom-watchman.spdx.json` | Syft `<version>` |
| Local Bridge | `sbom-local-bridge.json` | `sbom-local-bridge.spdx.json` | Syft `<version>` |

---

## Included non-image assets

| Asset class | Path in bundle | Version / notes |
|-------------|----------------|-----------------|
| Model catalog | `bundle/models/` | See `models/catalog.yaml` |
| Helm chart | `bundle/charts/e31-substrate/` | Chart version `<x.y.z>` |
| Lockfiles | `bundle/lockfiles/` | `uv.lock` set for `<commit>` |
| Runbooks | `bundle/runbooks/` | Includes air-gap provisioning |

---

## Test & reproducibility evidence

| Check | Result | Timestamp (UTC) | Evidence |
|-------|--------|-----------------|----------|
| Unit tests (`pytest …/tests/unit`) | PASS / FAIL | `<ts>` | `<CI artifact / log>` |
| Integration tests | PASS / FAIL | `<ts>` | `<CI artifact / log>` |
| Cosign image signatures | PASS / FAIL | `<ts>` | `<command output>` |
| Manifest signature | PASS / FAIL | `<ts>` | `<command output>` |
| `verify-reproducibility.sh` | PASS / FAIL | `<ts>` | Matching `bundle.sha256`: `<digest>` |

---

## Known issues / deviations

- `<None | describe any ephemeral-key CI runs, skipped registry publish, etc.>`

---

## Approvals

| Role | Name | Date (UTC) |
|------|------|------------|
| Release manager | | |
| Security custodian | | |
| Accreditation reviewer | | |
