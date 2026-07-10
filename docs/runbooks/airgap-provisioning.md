# Air-Gap Provisioning Runbook — E31 Czar Sealed Appliance

## Prerequisites

- Signed release bundle (`e31-release-<version>.tar`)
- Matching `manifest.sha256` + `manifest.sha256.sig`
- Cosign public key / trust root provisioned at manufacture
- k3s running on the Jetson AGX Thor target

## Steps

1. **Verify integrity**
   ```bash
   cosign verify-blob --key /etc/e31/cosign.pub \
     --signature manifest.sha256.sig manifest.sha256
   sha256sum -c <<< "$(awk 'NR==1{print $1"  "$2}' manifest.sha256)"
   ```

2. **Extract bundle**
   ```bash
   tar -xpf e31-release-<version>.tar
   cd bundle
   ```

3. **Load images into local registry**
   ```bash
   for d in images/*/; do
     name=$(basename "$d")
     skopeo copy "oci:${d}:v1" "docker://127.0.0.1:5000/${name}:v1"
   done
   ```

4. **Install Helm chart**
   ```bash
   helm upgrade --install e31-substrate charts/e31-substrate \
     -n e31-substrate --create-namespace
   ```

5. **Place model weights**
   ```bash
   rsync -a models/ /var/lib/e31/models/
   ```

6. **Confirm Watchman health**
   ```bash
   curl -sf http://127.0.0.1:9090/health
   ```

## Rollback

Retain the previous release bundle on the encrypted data volume. Re-load prior
image digests from `charts/e31-substrate/values.yaml` and re-apply Helm.
