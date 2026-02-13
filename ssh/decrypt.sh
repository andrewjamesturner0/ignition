#!/bin/bash
# decrypt.sh — Decrypt github.id_rsa.gpg to a destination path
# Usage: bash decrypt.sh <destination>
# Example: bash decrypt.sh /home/ajt/.ssh/github.id_rsa

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: bash decrypt.sh <destination>"
    exit 1
fi

DEST="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GPG_FILE="$SCRIPT_DIR/github.id_rsa.gpg"

if [[ ! -f "$GPG_FILE" ]]; then
    echo "Error: $GPG_FILE not found"
    exit 1
fi

gpg --decrypt --force-mdc --batch --yes --output "$DEST" "$GPG_FILE"
chmod 600 "$DEST"

echo "Decrypted to: $DEST (mode 600)"
