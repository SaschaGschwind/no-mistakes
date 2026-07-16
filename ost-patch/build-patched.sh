#!/usr/bin/env bash
#
# build-patched.sh - build the OST-vendored no-mistakes binary carrying the
# #501 fix (Azure DevOps PR description passed via temp file on Windows).
#
# This mirrors the Makefile `build`/`dist` LDFLAGS, but PINS a deliberately
# NON-SEMVER version (ost-nm-501). The self-updater treats any version it cannot
# parse as a development build (internal/update.isDevVersion), so this pin makes
# both the background upgrade-nag and `no-mistakes update` go inert: the binary
# will never try to replace itself with an upstream release and silently drop
# this patch. See ost-patch/README.md for the rationale.
#
# Output: dist/no-mistakes.exe (windows/amd64, CGO_ENABLED=0).
#
# Usage (from the repo root, with Go on PATH):
#   ./ost-patch/build-patched.sh

set -euo pipefail

# Resolve the repo root from this script's location so it can be run from
# anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# --- Version pin (the whole point of the vendored build) --------------------
VERSION="ost-nm-501"

# --- Build metadata (mirrors the Makefile) ----------------------------------
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Telemetry defaults (verbatim from the Makefile) ------------------------
UMAMI_HOST="https://a.kunchenguid.com"
UMAMI_WEBSITE_ID="f959e889-92f5-4121-8a1f-571b10861198"

PKG="github.com/kunchenguid/no-mistakes/internal/buildinfo"
LDFLAGS="-X ${PKG}.Version=${VERSION} \
-X ${PKG}.Commit=${COMMIT} \
-X ${PKG}.Date=${DATE} \
-X ${PKG}.TelemetryHost=${UMAMI_HOST} \
-X ${PKG}.TelemetryWebsiteID=${UMAMI_WEBSITE_ID}"

OUT="dist/no-mistakes.exe"
mkdir -p dist

echo "Building ${OUT}"
echo "  Version = ${VERSION} (non-semver pin -> self-update disabled)"
echo "  Commit  = ${COMMIT}"
echo "  Date    = ${DATE}"

CGO_ENABLED=0 GOOS=windows GOARCH=amd64 \
	go build -ldflags "${LDFLAGS}" -o "${OUT}" ./cmd/no-mistakes

echo "Built ${OUT}"
