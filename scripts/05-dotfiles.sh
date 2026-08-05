#!/bin/bash
# 05-dotfiles.sh - Run dotfiles installer

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_target_user "$TARGET_USER"
if [[ "$INVOCATION_MODE" != "target-user" ]]; then
    log_error "This script must be run as target user '$TARGET_USER'"
    exit 1
fi

DOTFILES_DIR="$TARGET_HOME/repos/dotfiles"

if [[ ! -d "$DOTFILES_DIR" ]]; then
    log_warn "Dotfiles repo not found at $DOTFILES_DIR, skipping"
    exit 0
fi

log_info "Installing dotfiles from $DOTFILES_DIR"

# Try known installer patterns in order of preference
if [[ -f "$DOTFILES_DIR/install.sh" ]]; then
    bash "$DOTFILES_DIR/install.sh"
elif [[ -f "$DOTFILES_DIR/Makefile" ]]; then
    case "$DISTRO_FAMILY" in
        arch)   MAKE_TARGET="arch" ;;
        debian) MAKE_TARGET="ubuntu" ;;
        *)
            log_error "Unsupported distro family '$DISTRO_FAMILY' (expected arch or debian)"
            exit 1
            ;;
    esac
    log_info "Detected $DISTRO_FAMILY family - running 'make $MAKE_TARGET'"
    make -C "$DOTFILES_DIR" "$MAKE_TARGET"
elif [[ -f "$DOTFILES_DIR/setup.sh" ]]; then
    bash "$DOTFILES_DIR/setup.sh"
else
    log_warn "No installer found in dotfiles repo (tried install.sh, Makefile, setup.sh)"
    exit 0
fi

log_info "Dotfiles installation complete"
