#!/bin/bash
# 05-dotfiles.sh — Run dotfiles installer

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

USERNAME="ajt"
DOTFILES_DIR="/home/$USERNAME/repos/dotfiles"

if [[ ! -d "$DOTFILES_DIR" ]]; then
    log_warn "Dotfiles repo not found at $DOTFILES_DIR, skipping"
    exit 0
fi

log_info "Installing dotfiles from $DOTFILES_DIR"

# Try known installer patterns in order of preference
if [[ -f "$DOTFILES_DIR/install.sh" ]]; then
    sudo -u "$USERNAME" bash "$DOTFILES_DIR/install.sh"
elif [[ -f "$DOTFILES_DIR/Makefile" ]]; then
    sudo -u "$USERNAME" make -C "$DOTFILES_DIR"
elif [[ -f "$DOTFILES_DIR/setup.sh" ]]; then
    sudo -u "$USERNAME" bash "$DOTFILES_DIR/setup.sh"
else
    log_warn "No installer found in dotfiles repo (tried install.sh, Makefile, setup.sh)"
    exit 0
fi

log_info "Dotfiles installation complete"
