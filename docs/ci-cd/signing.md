# Artifact Signing, SBOM Generation, and OCI Bundle Assembly

**Document type:** Accreditation runbook  
**Audience:** Release engineers, security assessors  
**Scripts:** [`assemble-release-bundle.sh`](../../e31-substrate/scripts/assemble-release-bundle.sh) · [`verify-reproducibility.sh`](../../e31-substrate/scripts/verify-reproducibility.sh)  
**Related:** [overview.md](overview.md) · [verification-checklist.md](verification-checklist.md)

---

## Cosign signing workflow

Every substrate service image is signed in the `sign` job (matrix over the seven services). The release **manifest** is signed again during bundle assembly so air-gap verifiers can trust the inventory without a live registry.

### Key management

| Item | Practice |
|------|----------|
| **Production private key** | Stored as GitHub Actions secret `COSIGN_KEY` (PEM or base64-encoded PEM). Never commit the private key. |
| **Passphrase** | If the key is encrypted, set `COSIGN_PASSWORD`. Cosign reads it from the environment. |
| **Public key / trust root** | Distribute `cosign.pub` to sealed appliances at manufacture (`/etc/e31/cosign.pub`). Rotate via controlled re-key ceremony; retain prior public keys for historical bundle verification. |
| **CI fallback** | If `COSIGN_KEY` is unset, CI runs `cosign generate-key-pair` and uses an ephemeral key. Signatures prove the pipeline path works but **must not** be used as a production trust root. |
| **Transparency log** | Air-gap builds prefer `--tlog-upload=false`. Online environments may upload to Rekor when reachable. |
| **Registry auth** | Use `REGISTRY_TOKEN` for `docker login` / `skopeo login` before any push of signed images or the OCI archive. |

Generate a production keypair offline:

```bash
cosign generate-key-pair
# Creates cosign.key (private) and cosign.pub (public)
# Store cosign.key in the secrets manager; provision cosign.pub on appliances
```

### Sample Cosign commands

**Sign a container image** (as in CI `sign` job):

```bash
export IMAGE_TAG="e31.local:5000/memory:${GITHUB_SHA}"
export COSIGN_PASSWORD="***"   # if key is encrypted

# Primary: key-based sign (offline-friendly)
cosign sign --yes --key /tmp/cosign.key --tlog-upload=false "${IMAGE_TAG}"

# Detached digest signature for air-gap transfer (sign-blob)
docker inspect --format='{{.Id}}' "${IMAGE_TAG}" > /tmp/image.digest
cosign sign-blob --yes --key /tmp/cosign.key --tlog-upload=false \
  --output-signature /tmp/image.sig \
  /tmp/image.digest
```

**Verify an image signature:**

```bash
cosign verify --key cosign.pub "e31.local:5000/memory:v1"
```

**Verify a detached blob / manifest signature:**

```bash
cosign verify-blob --key /etc/e31/cosign.pub \
  --signature manifest.sha256.sig \
  manifest.sha256
```

CI writes the Cosign key from the secret as follows:

1. If `COSIGN_KEY` contains `BEGIN`, write PEM text to `/tmp/cosign.key`.
2. Otherwise treat the secret as base64 and decode to `/tmp/cosign.key`.
3. `chmod 600` the key file before invoking Cosign.

---

## SBOM generation with Syft

The `sbom` job installs Syft and generates **JSON** and **SPDX-JSON** documents per service image.

### CLI invocation

```bash
export IMAGE_TAG_FULL="e31.local:5000/memory:${GITHUB_SHA}"

# Load image if working from CI tarball
gunzip -c /tmp/images/memory.tar.gz | docker load

# Syft JSON (primary CI artifact)
syft "docker:${IMAGE_TAG_FULL}" -o json > "sbom-memory.json"

# SPDX JSON (accreditation / SPDX consumers)
syft "docker:${IMAGE_TAG_FULL}" -o spdx-json > "sbom-memory.spdx.json"
```

Local builds via `build-services.sh` write SBOMs under `dist/artifacts/sboms/` when `SBOM=1` and `syft` is on `PATH`.

### Expected JSON output (shape)

Syft JSON is a document with schema metadata, source descriptor, and a `artifacts` array. Assessors should expect fields similar to:

```json
{
  "artifacts": [
    {
      "id": "pkg:generic/python@3.12...",
      "name": "python3",
      "version": "3.12.x",
      "type": "deb",
      "foundBy": "dpkg-db-cataloger",
      "locations": [
        { "path": "/var/lib/dpkg/status" }
      ],
      "licenses": [],
      "language": "",
      "cpes": [],
      "purl": "pkg:deb/ubuntu/python3@3.12...?arch=arm64"
    }
  ],
  "artifactRelationships": [],
  "source": {
    "type": "image",
    "target": {
      "userInput": "e31.local:5000/memory:<tag>",
      "imageID": "sha256:…",
      "manifestDigest": "sha256:…",
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "tags": ["e31.local:5000/memory:<tag>"]
    }
  },
  "distro": {
    "name": "ubuntu",
    "version": "24.04",
    "idLike": ["debian"]
  },
  "descriptor": {
    "name": "syft",
    "version": "<syft-version>"
  },
  "schema": {
    "version": "<syft-schema-version>",
    "url": "https://raw.githubusercontent.com/anchore/syft/main/schema/json/schema-<n>.json"
  }
}
```

Retain both `sbom-<service>.json` and `sbom-<service>.spdx.json` with the release for supply-chain attestation. Bundle assembly copies Syft JSON files into `release-bundle/sboms/` when present in the CI workspace.

---

## OCI release bundle assembly

### Script: `assemble-release-bundle.sh`

Assembles a content-addressed archive for offline provisioning.

#### Parameters

| Flag / env | Default | Description |
|------------|---------|-------------|
| `--registry REG` / `REGISTRY` | `e31.local:5000` | Source registry for skopeo image copy |
| `--tag TAG` / `TAG` | `v1` | Image tag to pull into the OCI layout |
| `--version VER` / `VERSION` | UTC timestamp | Bundle version string (CI uses 12-char git SHA) |
| `--out DIR` / `OUT_DIR` | `./dist/release-bundle` | Output directory |
| `--cosign-key PATH` / `COSIGN_KEY` | _(empty)_ | Private key path for **manifest** signing |
| `--release-repo URL` | _(empty)_ | Optional remote asset repo to clone/merge |
| `--skip-clone` / `SKIP_CLONE=1` | off | Skip clone; use local `release-bundle/` assets |
| `SOURCE_DATE_EPOCH` | git commit time | Deterministic mtimes for tar + `bundle.json` |
| `PLATFORM` | `linux/arm64` | Recorded in metadata |
| `COSIGN_PRIVATE_KEY` | — | Alternate: PEM in env if `--cosign-key` unset |

#### What the script does

1. **Merge assets** from `release-bundle/` (or cloned repo): models, charts, runbooks, lockfiles.
2. **Copy images** with skopeo into `bundle/images/<service>/` as OCI layouts (`oci:` transport); fall back to `docker-daemon:` if the registry is unreachable.
3. **Record digests** in `bundle/meta/image-digests.sha256` (content hash of each service OCI tree).
4. **Aggregate** repo `models/`, `charts/`, discovered `uv.lock` files, and `docs/runbooks/`.
5. **Write** `bundle/meta/bundle.json` with version, registry, services, `created_at` derived from `SOURCE_DATE_EPOCH`.
6. **Create deterministic tar** `e31-release-<version>.tar` (`--sort=name`, uid/gid 0, clamped mtime, POSIX pax without atime/ctime).
7. **Generate** `manifest.sha256` (tar hash + sorted per-file hashes under `bundle/`) and `bundle.sha256`.
8. **Sign the manifest** with Cosign (`sign-blob` → `manifest.sha256.sig`).
9. **Emit** `bundle-info.json` for CI/verify consumers.

#### Manifest signing

```bash
cosign sign-blob --yes --key "${COSIGN_KEY}" \
  --output-signature "${OUT_DIR}/manifest.sha256.sig" \
  --output-certificate "${OUT_DIR}/manifest.sha256.crt" \
  "${OUT_DIR}/manifest.sha256"
```

If no key is provided, the script writes a **placeholder** (SHA-256 of the manifest file) and prints a warning — unacceptable for production releases.

#### Example invocation (matches CI `bundle` job)

```bash
export SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)"
export VERSION="$(git rev-parse --short=12 HEAD)"
export COSIGN_PASSWORD="***"

bash e31-substrate/scripts/assemble-release-bundle.sh \
  --registry e31.local:5000 \
  --tag v1 \
  --version "${VERSION}" \
  --out dist/release-bundle \
  --cosign-key /tmp/cosign.key \
  --skip-clone
```

### Checksum verification

After assembly (or after receiving media):

```bash
cd dist/release-bundle

# Archive checksum
echo "$(cat bundle.sha256)  e31-release-${VERSION}.tar" | sha256sum -c -

# Full content-addressed inventory (first line is the tar)
sha256sum -c manifest.sha256

# Cosign signature over the manifest
cosign verify-blob --key cosign.pub \
  --signature manifest.sha256.sig \
  manifest.sha256
```

Reproducibility on a clean tree:

```bash
bash e31-substrate/scripts/verify-reproducibility.sh \
  --reference dist/release-bundle \
  --out dist/verify-bundle \
  --registry e31.local:5000 \
  --tag v1 \
  --version "${VERSION}" \
  --cosign-key /tmp/cosign.key
```

The verify script re-runs assembly and compares `bundle.sha256`, `bundle/meta/image-digests.sha256`, and the sorted content lines of `manifest.sha256`. Any mismatch exits non-zero.

---

## Bundle layout (OCI archive structure)

```text
dist/release-bundle/
├── e31-release-<version>.tar          # deterministic archive of bundle/
├── manifest.sha256                    # tar SHA-256 + per-file inventory
├── manifest.sha256.sig                # Cosign signature over manifest.sha256
├── bundle.sha256                      # archive checksum only
├── bundle-info.json                   # version + SOURCE_DATE_EPOCH + tar name
└── bundle/                            # also inside the tar
    ├── images/<service>/              # OCI layout (skopeo oci: transport)
    ├── images/jetpack/                # optional JetPack 7.2 base
    ├── models/                        # open-weight catalog assets
    ├── charts/                        # Helm charts (e31-substrate)
    ├── lockfiles/                     # uv.lock trees
    ├── runbooks/                      # ops runbooks
    └── meta/
        ├── bundle.json
        ├── image-digests.sha256
        └── <service>.files.sha256
```

On `main` pushes, CI attempts:

```bash
skopeo copy --dest-tls-verify=false \
  "oci-archive:dist/release-bundle/e31-release-<version>.tar" \
  "docker://e31.local:5000/e31-release:<version>"
```

Authenticate first with `REGISTRY_TOKEN` when the registry requires credentials. If publish fails, the workflow retains the air-gap tarball as a GitHub Actions artifact.
