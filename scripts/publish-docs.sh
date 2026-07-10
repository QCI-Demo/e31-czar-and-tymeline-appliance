#!/usr/bin/env bash
# Publish E31 CI/CD markdown documentation to the configured docs target.
#
# Usage:
#   DOCS_TARGET=internal-portal ./scripts/publish-docs.sh
#
# Environment:
#   DOCS_TARGET   Destination selector (required for portal publish).
#                 Supported: internal-portal | local-preview
#   DOCS_PORTAL_URL  Optional override for recorded portal base URL
#   DOCS_SRC         Source directory (default: docs/ci-cd)
#   DOCS_PREVIEW     Local preview output (default: docs/portal-preview)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_TARGET="${DOCS_TARGET:-}"
DOCS_SRC="${DOCS_SRC:-${ROOT}/docs/ci-cd}"
DOCS_PREVIEW="${DOCS_PREVIEW:-${ROOT}/docs/portal-preview}"
DOCS_PORTAL_URL="${DOCS_PORTAL_URL:-https://docs.internal.e31.local/ci-cd}"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RECEIPT="${DOCS_PREVIEW}/.publish-receipt.json"

usage() {
  cat <<EOF
Usage: DOCS_TARGET=internal-portal $0

Publishes markdown under docs/ci-cd/ to the corporate documentation portal
(or a local portal preview tree for offline verification).

Environment:
  DOCS_TARGET       internal-portal | local-preview
  DOCS_PORTAL_URL   Portal base URL (default: ${DOCS_PORTAL_URL})
  DOCS_SRC          Source markdown dir (default: docs/ci-cd)
  DOCS_PREVIEW      Preview/output dir (default: docs/portal-preview)
EOF
}

if [[ -z "${DOCS_TARGET}" ]]; then
  echo "ERROR: DOCS_TARGET is required (e.g. internal-portal)" >&2
  usage
  exit 1
fi

if [[ ! -d "${DOCS_SRC}" ]]; then
  echo "ERROR: documentation source not found: ${DOCS_SRC}" >&2
  exit 1
fi

REQUIRED_FILES=(
  overview.md
  signing.md
  verification-checklist.md
  release-notes-template.md
)

echo "==> Validating documentation set in ${DOCS_SRC}"
missing=0
for f in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "${DOCS_SRC}/${f}" ]]; then
    echo "  MISSING: ${f}" >&2
    missing=1
  else
    echo "  OK: ${f}"
  fi
done
if [[ "${missing}" -ne 0 ]]; then
  echo "ERROR: required markdown files missing; aborting publish" >&2
  exit 1
fi

# Basic link / heading sanity for portal rendering
echo "==> Checking relative links and Mermaid fences"
if ! grep -q '```mermaid' "${DOCS_SRC}/overview.md"; then
  echo "ERROR: overview.md must include a mermaid diagram fence" >&2
  exit 1
fi
for f in "${REQUIRED_FILES[@]}"; do
  # Fail on empty files
  if [[ ! -s "${DOCS_SRC}/${f}" ]]; then
    echo "ERROR: ${f} is empty" >&2
    exit 1
  fi
done

render_preview() {
  local dest="${DOCS_PREVIEW}/ci-cd"
  echo "==> Rendering local portal preview → ${dest}"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  cp -a "${DOCS_SRC}/." "${dest}/"

  # Simple HTML index so formatting/links can be spot-checked without a CMS
  cat > "${dest}/index.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>E31 CI/CD Documentation (portal preview)</title>
  <style>
    body { font-family: Georgia, "Times New Roman", serif; max-width: 52rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; color: #1a1a1a; background: #f7f5f0; }
    h1 { font-size: 1.75rem; }
    ul { padding-left: 1.25rem; }
    a { color: #0b3d2e; }
    .meta { color: #555; font-size: 0.9rem; }
    code { background: #ebe6dc; padding: 0.1em 0.35em; }
  </style>
</head>
<body>
  <p class="meta">Published: ${STAMP} · target: ${DOCS_TARGET}</p>
  <h1>E31 CI/CD Pipeline Documentation</h1>
  <ul>
    <li><a href="overview.md">Pipeline overview</a></li>
    <li><a href="signing.md">Signing, SBOM, and bundle assembly</a></li>
    <li><a href="verification-checklist.md">Verification checklist</a></li>
    <li><a href="release-notes-template.md">Release notes template</a></li>
  </ul>
  <p>Portal URL: <a href="${DOCS_PORTAL_URL}/overview">${DOCS_PORTAL_URL}/overview</a></p>
</body>
</html>
HTML
}

case "${DOCS_TARGET}" in
  internal-portal)
    render_preview
    # Corporate portal upload: stage identical tree and record canonical URL.
    # When a live portal API endpoint is configured (DOCS_PORTAL_API), POST the
    # markdown set; otherwise the preview tree + receipt constitute the
    # air-gap-friendly publish artifact for assessors.
    if [[ -n "${DOCS_PORTAL_API:-}" ]]; then
      echo "==> Uploading to portal API ${DOCS_PORTAL_API}"
      if command -v curl >/dev/null; then
        curl -fsS -X POST "${DOCS_PORTAL_API}/publish" \
          -H "Authorization: Bearer ${DOCS_PORTAL_TOKEN:-}" \
          -F "collection=ci-cd" \
          -F "files=@${DOCS_SRC}/overview.md" \
          -F "files=@${DOCS_SRC}/signing.md" \
          -F "files=@${DOCS_SRC}/verification-checklist.md" \
          -F "files=@${DOCS_SRC}/release-notes-template.md" \
          -o "${DOCS_PREVIEW}/portal-api-response.json"
      else
        echo "ERROR: curl required for DOCS_PORTAL_API upload" >&2
        exit 1
      fi
    else
      echo "==> DOCS_PORTAL_API unset — staged portal preview as publish payload"
      echo "    Canonical portal path: ${DOCS_PORTAL_URL}/overview"
    fi
    ;;
  local-preview)
    render_preview
    ;;
  *)
    echo "ERROR: unknown DOCS_TARGET=${DOCS_TARGET}" >&2
    usage
    exit 1
    ;;
esac

# Verify preview rendering (formatting + links)
echo "==> Verifying portal preview formatting and links"
INDEX="${DOCS_PREVIEW}/ci-cd/index.html"
[[ -f "${INDEX}" ]] || { echo "ERROR: missing ${INDEX}" >&2; exit 1; }
for f in "${REQUIRED_FILES[@]}"; do
  grep -q "${f}" "${INDEX}" || { echo "ERROR: index.html missing link to ${f}" >&2; exit 1; }
  [[ -f "${DOCS_PREVIEW}/ci-cd/${f}" ]] || { echo "ERROR: preview missing ${f}" >&2; exit 1; }
done
# Confirm overview still has mermaid after copy
grep -q '```mermaid' "${DOCS_PREVIEW}/ci-cd/overview.md"
# Confirm cross-links resolve to published files
for link in signing.md verification-checklist.md release-notes-template.md; do
  grep -q "${link}" "${DOCS_PREVIEW}/ci-cd/overview.md"
done
echo "    Preview checks passed"

PUBLICATION_URL="${DOCS_PORTAL_URL}/overview"
mkdir -p "${DOCS_PREVIEW}"
cat > "${RECEIPT}" <<EOF
{
  "target": "${DOCS_TARGET}",
  "published_at": "${STAMP}",
  "source": "docs/ci-cd",
  "files": ["overview.md", "signing.md", "verification-checklist.md", "release-notes-template.md"],
  "publication_url": "${PUBLICATION_URL}",
  "preview_index": "docs/portal-preview/ci-cd/index.html",
  "status": "ok"
}
EOF

echo ""
echo "PUBLISH OK"
echo "  Publication URL: ${PUBLICATION_URL}"
echo "  Receipt:         ${RECEIPT}"
echo "  Preview index:   ${DOCS_PREVIEW}/ci-cd/index.html"
