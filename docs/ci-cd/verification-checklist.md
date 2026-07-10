# CI/CD & Release Bundle Verification Checklist

**Document type:** Accreditation checklist  
**Epic:** Automated CI/CD Pipeline & Signed Release Bundle Creation  
**Story:** Document CI/CD Pipeline and Release Bundle Format  
**Related:** [overview.md](overview.md) · [signing.md](signing.md) · [release-notes-template.md](release-notes-template.md)

Use this checklist to confirm a release meets epic acceptance criteria. Mark each item only after evidence is attached (CI run URL, artifact digests, or local command output).

---

## Epic acceptance criteria

### Pipeline automation

- [ ] Workflow `.github/workflows/ci.yml` runs on `push` to `main` and on PRs targeting `main`
- [ ] Job `build` produces JetPack 7.2 base image and all seven service images for `linux/arm64`
- [ ] JetPack base is built from Ubuntu 24.04 pinned by digest (`sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90`)
- [ ] Service Dockerfiles are generated with `BASE_DIGEST` pinned via `generate-dockerfiles.sh`
- [ ] Job `test` executes unit and integration suites; JUnit XML uploaded as `test-results`
- [ ] Jobs `sign` and `sbom` run only after successful `build` and `test`
- [ ] Job `bundle` assembles the OCI release archive after `sign` and `sbom`
- [ ] Job `verify` re-assembles on a clean runner and fails the pipeline on digest mismatch

### Artifact signing (Cosign)

- [ ] Production `COSIGN_KEY` (and `COSIGN_PASSWORD` if encrypted) configured in CI secrets
- [ ] Each of the seven service images has a Cosign signature artifact (`signature-<service>/`)
- [ ] Detached `image.sig` / `image.digest` present for air-gap verification
- [ ] `manifest.sha256.sig` produced by `assemble-release-bundle.sh` using the release Cosign key
- [ ] `cosign verify` / `cosign verify-blob` succeeds against the site trust root (`cosign.pub`)
- [ ] Ephemeral CI keys (if used in non-prod) are **not** treated as the production trust root

### SBOM generation (Syft)

- [ ] Syft JSON SBOM exists for each service (`sbom-<service>.json`)
- [ ] SPDX JSON SBOM exists for each service (`sbom-<service>.spdx.json`)
- [ ] SBOM `source.target` references the signed image identity (tag / digest)
- [ ] SBOMs retained with the release artifacts for the accreditation package

### OCI release bundle contents

- [ ] Archive `e31-release-<version>.tar` present
- [ ] Bundle includes OCI layouts under `bundle/images/` for all seven services
- [ ] Bundle includes model catalog assets under `bundle/models/`
- [ ] Bundle includes Helm charts under `bundle/charts/`
- [ ] Bundle includes lockfiles (`uv.lock` trees) under `bundle/lockfiles/`
- [ ] Bundle includes runbooks under `bundle/runbooks/`
- [ ] `bundle/meta/bundle.json` records version, registry, platform, `source_date_epoch`
- [ ] `bundle/meta/image-digests.sha256` lists content digests per service
- [ ] `manifest.sha256` and `bundle.sha256` present and consistent with the tar

### Reproducibility

- [ ] `SOURCE_DATE_EPOCH` fixed to the release commit timestamp
- [ ] Second assembly (CI `verify` job or local `verify-reproducibility.sh`) yields identical `bundle.sha256`
- [ ] Image digest inventory matches between reference and re-assembly
- [ ] Sorted content lines of `manifest.sha256` match (excluding signature files)

### Offline / air-gap provisioning support

- [ ] Bundle transferable on approved media without requiring registry pull at the sealed site
- [ ] Manifest signature verifiable offline with provisioned `cosign.pub`
- [ ] Air-gap steps in `docs/runbooks/airgap-provisioning.md` executed successfully on a representative appliance (or lab twin)
- [ ] `REGISTRY_TOKEN` available for any pre-air-gap publish to the internal registry (build environment only)

### Documentation (this story)

- [ ] [overview.md](overview.md) describes purpose, artifact flow, jobs I/O, and includes a Mermaid diagram
- [ ] Build/test steps document pinned docker build, secrets (`COSIGN_KEY`, `REGISTRY_TOKEN`), and pytest discovery
- [ ] [signing.md](signing.md) covers Cosign, Syft, bundle parameters, and checksum verification
- [ ] [release-notes-template.md](release-notes-template.md) filled for the candidate release
- [ ] Docs published via `DOCS_TARGET=internal-portal ./scripts/publish-docs.sh`
- [ ] Publication URL recorded in the runbook ([overview.md](overview.md#publication))

---

## Operator sign-off

| Role | Name | Date (UTC) | Signature / initials |
|------|------|------------|----------------------|
| Build engineer | | | |
| Security / signing custodian | | | |
| Release manager | | | |
| Accreditation reviewer | | | |

**CI run URL:** _______________________________________________  
**Bundle version:** ___________________________________________  
**`bundle.sha256`:** __________________________________________
