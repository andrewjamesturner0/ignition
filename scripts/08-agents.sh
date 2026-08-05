#!/bin/bash
# 08-agents.sh - Install coding agents: Claude Code, Codex CLI, and pi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_target_user "$TARGET_USER"
if [[ "$INVOCATION_MODE" != "target-user" ]]; then
    log_error "This script must be run as target user '$TARGET_USER'"
    exit 1
fi

PI_PACKAGE="@earendil-works/pi-coding-agent"
OLD_PI_PACKAGE="@mariozechner/pi-coding-agent"
NVM_DIR="$TARGET_HOME/.nvm"
export NVM_DIR

ensure_file_line() {
    local file="$1"
    local line="$2"

    mkdir -p "$(dirname -- "$file")"
    touch "$file"
    if ! grep -qxF "$line" "$file"; then
        printf '%s\n' "$line" >> "$file"
    fi
    chmod 0644 "$file"
}

ensure_file_line "$TARGET_HOME/.profile" 'export PATH="$HOME/.local/bin:$PATH"'
ensure_file_line "$TARGET_HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"'

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
    nvm use --silent default >/dev/null 2>&1 || true
fi

npm_has_global() {
    npm list -g --depth=0 "$1" >/dev/null 2>&1
}

npm_uninstall_global() {
    npm uninstall -g "$1"
}

npm_install_global() {
    npm install -g "$@"
}

# Claude Code CLI
# Installed via upstream curl|bash; doesn't need Node.js pre-installed.

if command -v claude >/dev/null 2>&1; then
    log_info "claude already installed, skipping"
else
    log_info "Installing Claude Code CLI for user $TARGET_USER"
    curl -fsSL https://claude.ai/install.sh | bash
    log_info "claude installed"
fi

if ! npm_prefix="$(npm config get prefix 2>/dev/null)" \
    || [[ "$npm_prefix" != "$NVM_DIR"/versions/node/* ]]; then
    log_error "npm is not configured under nvm for $TARGET_USER; run the nodejs module before installing npm-based agents"
    exit 1
fi

# OpenAI Codex CLI
# Requires Node.js - 07-nodejs.sh must have run first.

if command -v codex >/dev/null 2>&1; then
    log_info "codex already installed, skipping"
else
    log_info "Installing Codex CLI for user $TARGET_USER"
    npm_install_global @openai/codex
    log_info "codex installed"
fi

# pi coding agent
# https://pi.dev - npm package.

if npm_has_global "$PI_PACKAGE"; then
    log_info "pi already installed, skipping"
else
    if npm_has_global "$OLD_PI_PACKAGE"; then
        log_info "Removing old pi package $OLD_PI_PACKAGE"
        npm_uninstall_global "$OLD_PI_PACKAGE"
    fi

    log_info "Installing pi coding agent for user $TARGET_USER"
    npm_install_global --ignore-scripts "$PI_PACKAGE"
    log_info "pi installed"
fi

log_info "Coding agents installation complete"
