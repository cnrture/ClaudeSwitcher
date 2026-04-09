#!/usr/bin/env bash
#
# update-appcast.sh — append a new <item> to docs/appcast.xml for a release
#
# Called by release.sh after the zip is signed, notarized, stapled, and the
# ed25519 signature has been computed via sign_update.
#
# Usage (typically from release.sh):
#   scripts/update-appcast.sh \
#       --version 1.0.1 \
#       --short-version 1.0.1 \
#       --zip release/ClaudeSwitcher.zip \
#       --ed-signature "abc123..." \
#       --length 194950 \
#       --release-notes "Added custom app icon and Sparkle auto-update."

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPCAST="${REPO_ROOT}/docs/appcast.xml"

VERSION=""
SHORT_VERSION=""
ZIP=""
ED_SIGNATURE=""
LENGTH=""
RELEASE_NOTES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)        VERSION="$2"; shift 2 ;;
        --short-version)  SHORT_VERSION="$2"; shift 2 ;;
        --zip)            ZIP="$2"; shift 2 ;;
        --ed-signature)   ED_SIGNATURE="$2"; shift 2 ;;
        --length)         LENGTH="$2"; shift 2 ;;
        --release-notes)  RELEASE_NOTES="$2"; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
    esac
done

[[ -n "${VERSION}" ]]       || { echo "missing --version" >&2; exit 1; }
[[ -n "${SHORT_VERSION}" ]] || SHORT_VERSION="${VERSION}"
[[ -n "${ED_SIGNATURE}" ]]  || { echo "missing --ed-signature" >&2; exit 1; }
[[ -n "${LENGTH}" ]]        || { echo "missing --length" >&2; exit 1; }
[[ -f "${APPCAST}" ]]       || { echo "appcast not found at ${APPCAST}" >&2; exit 1; }

DOWNLOAD_URL="https://github.com/cnrture/ClaudeSwitcher/releases/download/v${VERSION}/ClaudeSwitcher.zip"
PUB_DATE="$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S +0000")"
MIN_SYSTEM="13.0"

# escape CDATA-unsafe chars in release notes (just strip ]]> which would close the CDATA)
SAFE_NOTES="${RELEASE_NOTES//]]>/]]]]><![CDATA[>}"

ITEM=$(cat <<EOF
    <item>
      <title>Version ${SHORT_VERSION}</title>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_SYSTEM}</sparkle:minimumSystemVersion>
      <description><![CDATA[${SAFE_NOTES}]]></description>
      <pubDate>${PUB_DATE}</pubDate>
      <enclosure
        url="${DOWNLOAD_URL}"
        sparkle:edSignature="${ED_SIGNATURE}"
        length="${LENGTH}"
        type="application/octet-stream"/>
    </item>
EOF
)

# insert the new item immediately after the last <language>...</language> line
# so it becomes the newest entry in the channel
python3 - "${APPCAST}" <<PYEOF
import sys
path = sys.argv[1]
item = """${ITEM}"""
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()
marker = '</language>'
idx = content.find(marker)
if idx == -1:
    sys.stderr.write(f'error: could not find {marker!r} in {path}\n')
    sys.exit(1)
insert_at = idx + len(marker)
new = content[:insert_at] + '\n' + item + content[insert_at:]
with open(path, 'w', encoding='utf-8') as f:
    f.write(new)
print(f'appended v${VERSION} item to {path}')
PYEOF
