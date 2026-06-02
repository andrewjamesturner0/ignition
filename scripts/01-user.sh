#!/bin/bash
# 01-user.sh — Create target user with sudo privileges

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

if id "$TARGET_USER" &>/dev/null; then
    log_info "User $TARGET_USER already exists, skipping"
    exit 0
fi

log_info "Creating user $TARGET_USER"
useradd -m -s /bin/bash "$TARGET_USER"

case "$DISTRO_FAMILY" in
    debian)
        usermod -aG sudo "$TARGET_USER"
        log_info "Added $TARGET_USER to sudo group"
        ;;
    arch)
        usermod -aG wheel "$TARGET_USER"
        # Enable NOPASSWD for wheel group
        mkdir -p /etc/sudoers.d
        echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd
        chmod 440 /etc/sudoers.d/wheel-nopasswd
        log_info "Added $TARGET_USER to wheel group with NOPASSWD"
        ;;
    *)
        log_warn "Unknown distro family '$DISTRO_FAMILY'; skipping sudo setup"
        ;;
esac

log_info "User $TARGET_USER created successfully"
