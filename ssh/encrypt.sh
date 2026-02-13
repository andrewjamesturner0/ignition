#!/bin/bash
# encrypt.sh — Encrypt a plaintext SSH key to .gpg (AES-256, SHA-512 KDF, max iterations)
# Usage: bash encrypt.sh <keyfile>
# Example: bash encrypt.sh github.id_rsa
#   -> produces github.id_rsa.gpg

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: bash encrypt.sh <keyfile>"
    exit 1
fi

KEYFILE="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT="$SCRIPT_DIR/$KEYFILE"
OUTPUT="$INPUT.gpg"

if [[ ! -f "$INPUT" ]]; then
    echo "Error: $INPUT not found"
    exit 1
fi

if [[ -f "$OUTPUT" ]]; then
    echo "Error: $OUTPUT already exists; remove it first to re-encrypt"
    exit 1
fi

gpg --symmetric \
    --cipher-algo AES256 \
    --s2k-mode 3 \
    --s2k-digest-algo SHA512 \
    --s2k-count 65011712 \
    --force-mdc \
    --batch --yes \
    --output "$OUTPUT" "$INPUT"

echo "Encrypted: $OUTPUT"
echo ""
echo "Verify with:  bash decrypt.sh /tmp/test-key && diff $KEYFILE /tmp/test-key && rm /tmp/test-key"
echo ""
echo "Then securely remove the plaintext:"
echo "  shred -u $KEYFILE && git rm $KEYFILE"
