#!/bin/bash
# 02-packages.sh — Install core dev packages

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

case "$DISTRO_FAMILY" in
    debian)
        log_info "Installing packages via apt"
        apt update
        apt install -y \
            build-essential make cmake m4 \
            vim tmux git curl wget \
            python3 python3-pip python3-venv \
            ripgrep fd-find fzf jq \
            gnupg openssh-client \
            btop htop \
            stow software-properties-common
        ;;
    arch)
        log_info "Installing packages via pacman"
        pacman -Syu --noconfirm
        pacman -S --noconfirm --needed \
            base base-devel cmake m4 \
            vim tmux git curl wget \
            python python-pip \
            ripgrep fd fzf jq \
            gnupg openssh \
            btop htop \
            stow
        ;;
    *)
        log_error "Unsupported distro family: $DISTRO_FAMILY"
        exit 1
        ;;
esac

log_info "Package installation complete"
