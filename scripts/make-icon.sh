#!/usr/bin/env bash
#
# make-icon.sh — convert a 1024x1024 PNG into ClaudeSwitcher/Resources/AppIcon.icns
#
# Usage:
#   ./scripts/make-icon.sh                     # uses ClaudeSwitcher/Resources/AppIcon.png
#   ./scripts/make-icon.sh /path/to/source.png # uses the specified source
#
# The source PNG should be 1024x1024. macOS apps render best when the icon's
# visible content sits inside an 824x824 box centered in the canvas (100px
# padding on each side), per Apple's Human Interface Guidelines for macOS
# app icons.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_SOURCE="${REPO_ROOT}/ClaudeSwitcher/Resources/AppIcon.png"

SOURCE="${1:-${DEFAULT_SOURCE}}"
if [[ ! -f "${SOURCE}" ]]; then
    echo "error: source PNG not found: ${SOURCE}" >&2
    echo "       place your 1024x1024 master at ClaudeSwitcher/Resources/AppIcon.png" >&2
    echo "       or pass a path as the first argument" >&2
    exit 1
fi

command -v sips >/dev/null     || { echo "error: sips not found" >&2; exit 1; }
command -v iconutil >/dev/null || { echo "error: iconutil not found" >&2; exit 1; }

RESOURCES_DIR="${REPO_ROOT}/ClaudeSwitcher/Resources"
ICONSET="${RESOURCES_DIR}/AppIcon.iconset"
ICNS="${RESOURCES_DIR}/AppIcon.icns"

# verify source dimensions
WIDTH=$(sips -g pixelWidth "${SOURCE}" | awk '/pixelWidth/{print $2}')
HEIGHT=$(sips -g pixelHeight "${SOURCE}" | awk '/pixelHeight/{print $2}')
if [[ "${WIDTH}" != "1024" || "${HEIGHT}" != "1024" ]]; then
    echo "warning: source is ${WIDTH}x${HEIGHT}, expected 1024x1024"
    echo "         continuing anyway; result may be blurry"
fi

mkdir -p "${RESOURCES_DIR}"
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

# each entry: "<pixels>:<filename>"
# iconutil requires this exact set of filenames for a complete .icns
SIZES=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
    IFS=':' read -r size name <<< "${entry}"
    sips -z "${size}" "${size}" "${SOURCE}" --out "${ICONSET}/${name}" >/dev/null
done

iconutil -c icns "${ICONSET}" -o "${ICNS}"
rm -rf "${ICONSET}"

echo "==> wrote ${ICNS}"
echo "    next: run ./scripts/release.sh to rebuild a signed/notarized .app with the new icon"
