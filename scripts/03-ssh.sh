#!/bin/bash
# 03-ssh.sh - Decrypt and install SSH keys for target user

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_target_user "$TARGET_USER"
if [[ "$INVOCATION_MODE" != "target-user" ]]; then
    log_error "This script must be run as target user '$TARGET_USER'"
    exit 1
fi

SSH_DIR="$TARGET_HOME/.ssh"
REPO_SSH_DIR="$SCRIPT_DIR/../ssh"

log_info "Setting up SSH for $TARGET_USER"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ -f "$REPO_SSH_DIR/github.id_rsa.gpg" ]]; then
    log_info "Decrypting SSH private key"
    bash "$REPO_SSH_DIR/decrypt.sh" "$SSH_DIR/github.id_rsa"
else
    log_error "Encrypted key not found at $REPO_SSH_DIR/github.id_rsa.gpg"
    exit 1
fi

if [[ -f "$REPO_SSH_DIR/config" ]]; then
    install -m 0644 "$REPO_SSH_DIR/config" "$SSH_DIR/config"
    log_info "Copied SSH config"
fi

chmod 600 "$SSH_DIR/github.id_rsa"

log_info "SSH setup complete"
