#!/bin/bash
# Install core development packages, or check them with --check.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

DEBIAN_PACKAGES=(
    build-essential make cmake m4
    vim tmux git curl wget
    python3 python3-pip python3-venv
    ripgrep fd-find fzf jq
    gnupg openssh-client
    btop htop sudo
    stow software-properties-common
)

ARCH_PACKAGES=(
    base base-devel cmake m4
    vim tmux git curl wget
    python python-pip
    ripgrep fd fzf jq
    gnupg openssh
    btop htop sudo
    stow
)

packages_are_installed() {
    local package

    case "$DISTRO_FAMILY" in
        debian)
            for package in "${DEBIAN_PACKAGES[@]}"; do
                [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" == "install ok installed" ]] || return 1
            done
            ;;
        arch)
            for package in "${ARCH_PACKAGES[@]}"; do
                pacman -Q "$package" &>/dev/null || return 1
            done
            ;;
        *)
            return 1
            ;;
    esac
}

if [[ "${1:-}" == "--check" ]]; then
    [[ $# -eq 1 ]] || exit 2
    packages_are_installed
    exit
elif [[ $# -ne 0 ]]; then
    log_error "Usage: bash 02-packages.sh [--check]"
    exit 2
fi

require_root

case "$DISTRO_FAMILY" in
    debian)
        log_info "Installing packages via apt"
        apt update
        apt install -y "${DEBIAN_PACKAGES[@]}"
        ;;
    arch)
        log_info "Installing packages via pacman"
        pacman -Syu --noconfirm
        pacman -S --noconfirm --needed "${ARCH_PACKAGES[@]}"
        ;;
    *)
        log_error "Unsupported distro family: $DISTRO_FAMILY"
        exit 1
        ;;
esac

log_info "Package installation complete"
