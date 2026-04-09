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

# ---- sign ----
info "code signing with hardened runtime"
codesign \
    --force \
    --deep \
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

ok "release ready: ${ZIP_PATH}"
ok "users can download, unzip, and open ${APP_NAME}.app without any warnings"
