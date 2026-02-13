#!/bin/bash
# 01-user.sh — Create ajt user with sudo privileges

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

USERNAME="ajt"

if id "$USERNAME" &>/dev/null; then
    log_info "User $USERNAME already exists, skipping"
    exit 0
fi

log_info "Creating user $USERNAME"
useradd -m -s /bin/bash "$USERNAME"

case "$DISTRO_FAMILY" in
    debian)
        usermod -aG sudo "$USERNAME"
        log_info "Added $USERNAME to sudo group"
        ;;
    arch)
        usermod -aG wheel "$USERNAME"
        # Enable NOPASSWD for wheel group
        mkdir -p /etc/sudoers.d
        echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd
        chmod 440 /etc/sudoers.d/wheel-nopasswd
        log_info "Added $USERNAME to wheel group with NOPASSWD"
        ;;
    *)
        log_warn "Unknown distro family '$DISTRO_FAMILY'; skipping sudo setup"
        ;;
esac

log_info "User $USERNAME created successfully"
