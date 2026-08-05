#!/bin/bash
# 07-nodejs-system.sh - Install system prerequisites for nvm and Node.js

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

case "$DISTRO_FAMILY" in
    debian)
        log_info "Installing nvm prerequisites via apt"
        apt install -y ca-certificates curl git xz-utils
        ;;
    arch)
        log_info "Installing nvm prerequisites via pacman"
        pacman -S --noconfirm --needed curl git xz
        ;;
    *)
        log_error "Unsupported distro family: $DISTRO_FAMILY"
        exit 1
        ;;
esac

log_info "Node.js system prerequisites complete"
