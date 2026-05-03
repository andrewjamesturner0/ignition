#!/bin/bash
# 08-nodejs.sh — Install Node.js (default 20), npm, and nvm
# On Debian/Ubuntu uses NodeSource to get current versions (repos are stale).
# On Arch uses pacman.
# nvm is installed for the user so they can manage Node versions themselves.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

NODE_USER="ajt"
NODE_MAJOR="20"

case "$DISTRO_FAMILY" in
    debian)
        log_info "Installing Node.js $NODE_MAJOR via NodeSource (apt packages are stale)"

        # NodeSource setup script — one-liner that configures apt
        curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -

        apt install -y nodejs
        ;;
    arch)
        log_info "Installing Node.js + npm via pacman"
        pacman -S --noconfirm --needed nodejs npm
        ;;
    *)
        log_error "Unsupported distro family: $DISTRO_FAMILY"
        exit 1
        ;;
esac

log_info "node: $(node --version 2>/dev/null || echo 'not found')"
log_info "npm:  $(npm --version 2>/dev/null || echo 'not found')"

# ── nvm for the user ────────────────────────────────────────────────

log_info "Installing nvm for user $NODE_USER"

NVM_DIR="/home/$NODE_USER/.nvm"

# Install nvm as the target user (only if not already present)
if su - "$NODE_USER" -c "[ -s '$NVM_DIR/nvm.sh' ]"; then
    log_info "nvm already installed, skipping"
else
    su - "$NODE_USER" -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'
fi

# Install Node $NODE_MAJOR via nvm so the user has it in their nvm inventory
su - "$NODE_USER" -c "
    export NVM_DIR=\"$NVM_DIR\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    nvm install $NODE_MAJOR
"

log_info "Node.js + npm + nvm installation complete"
