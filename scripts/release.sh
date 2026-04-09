#!/usr/bin/env bash
#
# Release script: build, sign, notarize, staple, and package ClaudeSwitcher.app
#
# Requirements:
#   - Xcode command-line tools
#   - A "Developer ID Application" certificate in your keychain
#   - A notarytool keychain profile (see scripts/README.md for setup)
#
# Usage:
#   ./scripts/release.sh
#
# Configuration via environment variables (override the defaults below):
#   SIGNING_IDENTITY       — Developer ID Application identity
#   NOTARY_PROFILE         — notarytool keychain profile name
#   BUNDLE_ID              — app bundle identifier

set -euo pipefail

# ---- config ----
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: CANER TURE (39Z244SGXG)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ClaudeSwitcherNotary}"
BUNDLE_ID="${BUNDLE_ID:-com.candroid.ClaudeSwitcher}"
SPARKLE_TOOLS="${SPARKLE_TOOLS:-${HOME}/.sparkle-tools/bin}"
APPCAST_FILE_REL="docs/appcast.xml"
RELEASE_URL_PREFIX="https://github.com/cnrture/ClaudeSwitcher/releases/download"

# ---- paths ----
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/.build"
RELEASE_DIR="${REPO_ROOT}/release"
APP_NAME="ClaudeSwitcher"
APP_BUNDLE="${RELEASE_DIR}/${APP_NAME}.app"
ENTITLEMENTS="${REPO_ROOT}/ClaudeSwitcher.entitlements"
INFO_PLIST_SRC="${REPO_ROOT}/ClaudeSwitcher/Info.plist"
ZIP_NAME="${APP_NAME}.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"

# ---- helpers ----
info()  { printf "\033[1;34m==>\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m==>\033[0m %s\n" "$*"; }
fail()  { printf "\033[1;31m==>\033[0m %s\n" "$*" >&2; exit 1; }

# ---- preflight ----
command -v swift >/dev/null      || fail "swift not found (install Xcode command-line tools)"
command -v codesign >/dev/null   || fail "codesign not found"
command -v xcrun >/dev/null      || fail "xcrun not found"
[[ -f "${INFO_PLIST_SRC}" ]]     || fail "Info.plist missing at ${INFO_PLIST_SRC}"
[[ -f "${ENTITLEMENTS}" ]]       || fail "entitlements missing at ${ENTITLEMENTS}"

security find-identity -v -p codesigning 2>/dev/null | grep -qF "${SIGNING_IDENTITY}" \
    || fail "signing identity not found in keychain: ${SIGNING_IDENTITY}"

xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1 \
    || fail "notarytool profile '${NOTARY_PROFILE}' not found. See scripts/README.md to set it up."

[[ -x "${SPARKLE_TOOLS}/sign_update" ]] \
    || fail "Sparkle sign_update not found at ${SPARKLE_TOOLS}. Run ./scripts/setup-sparkle-tools.sh first."

# ---- clean ----
info "cleaning previous build artifacts"
rm -rf "${APP_BUNDLE}" "${ZIP_PATH}"
mkdir -p "${RELEASE_DIR}"

# ---- build universal binary ----
info "building universal release binary (arm64 + x86_64)"
swift build \
    -c release \
    --arch arm64 \
    --arch x86_64 \
    --package-path "${REPO_ROOT}"

BINARY_PATH="${BUILD_DIR}/apple/Products/Release/${APP_NAME}"
[[ -f "${BINARY_PATH}" ]] || fail "expected binary not found at ${BINARY_PATH}"

# ---- assemble .app bundle ----
info "assembling .app bundle"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

mkdir -p "${APP_BUNDLE}/Contents/Frameworks"

cp "${BINARY_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${INFO_PLIST_SRC}" "${APP_BUNDLE}/Contents/Info.plist"

# regenerate AppIcon.icns from the master PNG if present, then bundle it
ICON_PNG="${REPO_ROOT}/ClaudeSwitcher/Resources/AppIcon.png"
ICON_ICNS="${REPO_ROOT}/ClaudeSwitcher/Resources/AppIcon.icns"
if [[ -f "${ICON_PNG}" ]]; then
    info "regenerating AppIcon.icns from master PNG"
    "${REPO_ROOT}/scripts/make-icon.sh" >/dev/null
    cp "${ICON_ICNS}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    info "bundled AppIcon.icns"
elif [[ -f "${ICON_ICNS}" ]]; then
    info "using existing AppIcon.icns (no master PNG found)"
    cp "${ICON_ICNS}" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
else
    info "no AppIcon found — bundle will ship without a custom icon"
fi

# copy SPM-generated resource bundle if present
RESOURCE_BUNDLE="${BUILD_DIR}/apple/Products/Release/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "${RESOURCE_BUNDLE}" ]]; then
    cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
fi

# ---- bundle Sparkle.framework ----
info "locating Sparkle.framework in SPM artifact cache"
SPARKLE_SRC=$(find "${BUILD_DIR}" -type d -name "Sparkle.framework" -path "*macos*" 2>/dev/null | head -1)
if [[ -z "${SPARKLE_SRC}" ]]; then
    # fallback: any Sparkle.framework under .build
    SPARKLE_SRC=$(find "${BUILD_DIR}" -type d -name "Sparkle.framework" 2>/dev/null | head -1)
fi
[[ -d "${SPARKLE_SRC}" ]] || fail "could not find Sparkle.framework in ${BUILD_DIR}. did swift build resolve Sparkle?"
info "copying Sparkle.framework from ${SPARKLE_SRC}"
cp -R "${SPARKLE_SRC}" "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"

# ---- sign ----
# Nested components inside Sparkle.framework must be signed inside-out before
# the outer .app bundle. --deep alone is unreliable for XPC services, so we
# walk the tree explicitly.

SPARKLE_FW="${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="${SPARKLE_FW}/Versions/B"
[[ -d "${SPARKLE_VERSION_DIR}" ]] || SPARKLE_VERSION_DIR="${SPARKLE_FW}/Versions/A"

sign_nested() {
    local target="$1"
    [[ -e "${target}" ]] || return 0
    codesign --force --options runtime --timestamp \
        --sign "${SIGNING_IDENTITY}" "${target}"
}

info "signing Sparkle XPC services and helpers"
sign_nested "${SPARKLE_VERSION_DIR}/XPCServices/Downloader.xpc"
sign_nested "${SPARKLE_VERSION_DIR}/XPCServices/Installer.xpc"
sign_nested "${SPARKLE_VERSION_DIR}/Autoupdate"
sign_nested "${SPARKLE_VERSION_DIR}/Updater.app"

info "signing Sparkle.framework"
codesign --force --options runtime --timestamp \
    --sign "${SIGNING_IDENTITY}" "${SPARKLE_FW}"

info "code signing the app bundle with hardened runtime"
codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --identifier "${BUNDLE_ID}" \
    --sign "${SIGNING_IDENTITY}" \
    "${APP_BUNDLE}"

info "verifying signature"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

# ---- create zip for notarization ----
info "creating notarization archive"
/usr/bin/ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

# ---- notarize ----
info "submitting to Apple notary service (this may take a few minutes)"
xcrun notarytool submit "${ZIP_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

# ---- staple ----
info "stapling notarization ticket to .app"
xcrun stapler staple "${APP_BUNDLE}"
xcrun stapler validate "${APP_BUNDLE}"

# ---- final archive ----
info "creating final distribution archive"
rm -f "${ZIP_PATH}"
/usr/bin/ditto -c -k --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

# ---- gatekeeper sanity check ----
info "gatekeeper assessment"
spctl -a -vvv -t install "${APP_BUNDLE}" 2>&1 || true

# ---- sign the release zip for Sparkle ----
info "signing release zip with Sparkle sign_update"
SIGN_OUTPUT=$("${SPARKLE_TOOLS}/sign_update" "${ZIP_PATH}")
# sign_update output looks like: sparkle:edSignature="..." length="..."
ED_SIGNATURE=$(echo "${SIGN_OUTPUT}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "${SIGN_OUTPUT}" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
[[ -n "${ED_SIGNATURE}" ]] || fail "could not extract ed25519 signature from sign_update output: ${SIGN_OUTPUT}"
[[ -n "${LENGTH}" ]] || fail "could not extract length from sign_update output: ${SIGN_OUTPUT}"
info "ed25519 signature: ${ED_SIGNATURE:0:16}..."

# ---- update appcast ----
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${INFO_PLIST_SRC}")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${INFO_PLIST_SRC}")
RELEASE_NOTES_FILE="${REPO_ROOT}/RELEASE_NOTES_${VERSION}.md"
if [[ -f "${RELEASE_NOTES_FILE}" ]]; then
    RELEASE_NOTES_CONTENT=$(cat "${RELEASE_NOTES_FILE}")
else
    RELEASE_NOTES_CONTENT="Version ${VERSION}"
fi

info "updating ${APPCAST_FILE_REL} with v${VERSION} entry"
"${REPO_ROOT}/scripts/update-appcast.sh" \
    --version "${VERSION}" \
    --short-version "${VERSION}" \
    --zip "${ZIP_PATH}" \
    --ed-signature "${ED_SIGNATURE}" \
    --length "${LENGTH}" \
    --release-notes "${RELEASE_NOTES_CONTENT}"

ok "release ready: ${ZIP_PATH}"
ok "appcast updated: ${REPO_ROOT}/${APPCAST_FILE_REL}"
ok ""
ok "next steps (manual):"
ok "  1. git add ${APPCAST_FILE_REL} && git commit -m 'release: appcast entry for v${VERSION}' && git push"
ok "  2. gh release create v${VERSION} ${ZIP_PATH} --title 'ClaudeSwitcher v${VERSION}' --notes-file ${RELEASE_NOTES_FILE}"
ok "  3. shasum -a 256 ${ZIP_PATH}  # update homebrew-tap cask with new version + sha256"
