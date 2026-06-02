#!/bin/bash
# 03-ssh.sh — Decrypt and install SSH keys for target user

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

SSH_DIR="$TARGET_HOME/.ssh"
REPO_SSH_DIR="$SCRIPT_DIR/../ssh"

log_info "Setting up SSH for $TARGET_USER"

# Create .ssh directory
mkdir -p "$SSH_DIR"

# Decrypt private key
if [[ -f "$REPO_SSH_DIR/github.id_rsa.gpg" ]]; then
    log_info "Decrypting SSH private key"
    bash "$REPO_SSH_DIR/decrypt.sh" "$SSH_DIR/github.id_rsa"
else
    log_error "Encrypted key not found at $REPO_SSH_DIR/github.id_rsa.gpg"
    exit 1
fi

# Copy SSH config
if [[ -f "$REPO_SSH_DIR/config" ]]; then
    cp "$REPO_SSH_DIR/config" "$SSH_DIR/config"
    log_info "Copied SSH config"
fi

# Set ownership and permissions
chown -R "$TARGET_USER:$TARGET_USER" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/github.id_rsa"
chmod 644 "$SSH_DIR/config"

log_info "SSH setup complete"
