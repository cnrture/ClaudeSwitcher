#!/usr/bin/env bash
#
# backup-sparkle-key.sh — export the Sparkle ed25519 private key so you can
# store it in a password manager (1Password, Bitwarden, Apple Passwords, etc.)
#
# The key lives in your macOS login Keychain after running generate_keys.
# This script:
#   1. Exports the private key to a temporary file
#   2. Prints the contents to stdout with instructions for manual backup
#   3. Securely deletes the temp file
#
# It does NOT upload, email, or transmit the key anywhere. You must copy
# the output into your password manager yourself.
#
# WARNING: if you lose this key, every current and future ClaudeSwitcher user
# is locked on the version they already have. There is no recovery.

set -euo pipefail

TOOLS_DIR="${HOME}/.sparkle-tools"
GEN="${TOOLS_DIR}/bin/generate_keys"

if [[ ! -x "${GEN}" ]]; then
    printf "\033[1;31merror:\033[0m generate_keys not found at %s\n" "${GEN}" >&2
    printf "       run ./scripts/setup-sparkle-tools.sh first\n" >&2
    exit 1
fi

TMP_FILE="$(mktemp -t sparkle-backup.XXXXXX)"
trap 'test -f "${TMP_FILE}" && rm -P "${TMP_FILE}"' EXIT

# generate_keys -x <path> exports the existing private key to the given file
"${GEN}" -x "${TMP_FILE}" >/dev/null 2>&1 || {
    printf "\033[1;31merror:\033[0m generate_keys failed to export the private key\n" >&2
    printf "       have you run '%s' yet? the keychain entry must exist first\n" "${GEN}" >&2
    exit 1
}

if [[ ! -s "${TMP_FILE}" ]]; then
    printf "\033[1;31merror:\033[0m exported key file is empty\n" >&2
    exit 1
fi

cat <<'EOF'

================================================================================
  SPARKLE PRIVATE KEY BACKUP

  Copy EVERYTHING between the BEGIN and END lines below into your password
  manager as a Secure Note. Suggested metadata:

    Title: ClaudeSwitcher Sparkle ed25519 private key
    Tags:  sparkle, ed25519, claudeswitcher, critical
    Notes: If this key is lost, no future ClaudeSwitcher update can be signed
           for existing users. There is no recovery. Keep this backup forever.

  DO NOT email this, DO NOT commit it to git, DO NOT paste it into chat.

================================================================================
EOF

echo
echo "----- BEGIN SPARKLE PRIVATE KEY -----"
cat "${TMP_FILE}"
echo "----- END SPARKLE PRIVATE KEY -----"
echo
echo "(the temporary file at ${TMP_FILE} will be securely deleted when this script exits)"
echo
