#!/usr/bin/env bash
#
# setup-sparkle-tools.sh — one-time: download Sparkle CLI tools to ~/.sparkle-tools
#
# Sparkle ships three tools we need for the release pipeline:
#   - generate_keys    (one-time: create ed25519 key pair, store private in Keychain)
#   - sign_update      (per-release: produce ed25519 signature over a zip)
#   - generate_appcast (per-release: build/update the appcast feed)
#
# These live inside the Sparkle distribution tarball on GitHub Releases. We
# download a pinned version once and stash them in ~/.sparkle-tools so they
# survive `swift package clean` and aren't checked into the repo.
#
# Usage:
#   ./scripts/setup-sparkle-tools.sh                # installs default pinned version
#   SPARKLE_VERSION=2.9.1 ./scripts/setup-sparkle-tools.sh  # pin explicitly

set -euo pipefail

SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.1}"
TOOLS_DIR="${HOME}/.sparkle-tools"
BIN_DIR="${TOOLS_DIR}/bin"
VERSION_FILE="${TOOLS_DIR}/.version"

info()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m==>\033[0m %s\n" "$*"; }
fail()  { printf "\033[1;31m==>\033[0m %s\n" "$*" >&2; exit 1; }

command -v curl >/dev/null || fail "curl not found"
command -v tar >/dev/null  || fail "tar not found"

# skip if already installed at the requested version
if [[ -f "${VERSION_FILE}" ]] && [[ "$(cat "${VERSION_FILE}")" == "${SPARKLE_VERSION}" ]] \
    && [[ -x "${BIN_DIR}/generate_keys" ]] \
    && [[ -x "${BIN_DIR}/sign_update" ]]; then
    ok "Sparkle tools ${SPARKLE_VERSION} already installed at ${TOOLS_DIR}"
    exit 0
fi

TARBALL="Sparkle-${SPARKLE_VERSION}.tar.xz"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/${TARBALL}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

info "downloading ${TARBALL}"
curl -sSLf "${URL}" -o "${TMP_DIR}/${TARBALL}" \
    || fail "failed to download ${URL}"

info "extracting"
tar -xf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}"

# Sparkle's tarball layout: bin/ at the root, sibling to Sparkle.framework
EXTRACTED_BIN="${TMP_DIR}/bin"
[[ -d "${EXTRACTED_BIN}" ]] || fail "expected bin/ at root of tarball, not found"
[[ -x "${EXTRACTED_BIN}/generate_keys" ]] || fail "generate_keys missing in tarball"
[[ -x "${EXTRACTED_BIN}/sign_update" ]] || fail "sign_update missing in tarball"

info "installing to ${BIN_DIR}"
mkdir -p "${BIN_DIR}"
rm -f "${BIN_DIR}"/*
cp "${EXTRACTED_BIN}/generate_keys" "${BIN_DIR}/"
cp "${EXTRACTED_BIN}/sign_update" "${BIN_DIR}/"
cp "${EXTRACTED_BIN}/generate_appcast" "${BIN_DIR}/" 2>/dev/null || true
chmod +x "${BIN_DIR}"/*
echo "${SPARKLE_VERSION}" > "${VERSION_FILE}"

ok "installed Sparkle ${SPARKLE_VERSION} tools to ${BIN_DIR}"
echo
echo "Next steps:"
echo "  1. Generate the ed25519 key pair (one-time):"
echo "       ${BIN_DIR}/generate_keys"
echo "     This stores the private key in your macOS login Keychain and prints"
echo "     the public key to stdout. Copy the public key into Info.plist as"
echo "     the value of SUPublicEDKey."
echo
echo "  2. Back the key up off-machine — run:"
echo "       ./scripts/backup-sparkle-key.sh"
echo
echo "     IMPORTANT: if you lose the private key, you can never sign another"
echo "     release that existing users will accept. There is no recovery."
