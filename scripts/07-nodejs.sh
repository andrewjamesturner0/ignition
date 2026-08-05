#!/bin/bash
# 07-nodejs.sh - Install nvm, Node.js, and npm as the target user

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_target_user "$TARGET_USER"
if [[ "$INVOCATION_MODE" != "target-user" ]]; then
    log_error "This script must be run as target user '$TARGET_USER'"
    exit 1
fi

NODE_MAJOR="${NODE_MAJOR:-24}"
NVM_VERSION="${NVM_VERSION:-v0.40.4}"
NVM_DIR="$TARGET_HOME/.nvm"
export NVM_DIR

ensure_file_line() {
    local file="$1"
    local line="$2"

    mkdir -p "$(dirname "$file")"
    touch "$file"
    if ! grep -qxF "$line" "$file"; then
        printf '%s\n' "$line" >> "$file"
    fi
    chmod 0644 "$file"
}

log_info "Installing nvm $NVM_VERSION for user $TARGET_USER"

ensure_file_line "$TARGET_HOME/.profile" 'export PATH="$HOME/.local/bin:$PATH"'
ensure_file_line "$TARGET_HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"'

# Wire nvm into interactive and login shells.
ensure_file_line "$TARGET_HOME/.profile" 'export NVM_DIR="$HOME/.nvm"'
ensure_file_line "$TARGET_HOME/.profile" '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
ensure_file_line "$TARGET_HOME/.bashrc" 'export NVM_DIR="$HOME/.nvm"'
ensure_file_line "$TARGET_HOME/.bashrc" '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    log_info "nvm already installed, skipping"
else
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
fi

log_info "Installing Node.js $NODE_MAJOR under nvm for user $TARGET_USER"

# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"
nvm install "$NODE_MAJOR"
nvm alias default "$NODE_MAJOR"
nvm use --silent default
npm config delete prefix >/dev/null 2>&1 || true

npm_prefix="$(npm config get prefix)"
case "$npm_prefix" in
    "$NVM_DIR"/versions/node/*)
        ;;
    *)
        log_error "npm prefix is outside nvm: $npm_prefix"
        exit 1
        ;;
esac

log_info "user node: $(node --version 2>/dev/null || echo 'not found')"
log_info "user npm:  $(npm --version 2>/dev/null || echo 'not found')"

log_info "Node.js + npm + nvm installation complete"
