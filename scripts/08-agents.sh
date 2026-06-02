#!/bin/bash
# 08-agents.sh — Install coding agents: Claude Code, Codex CLI, and pi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

PI_PACKAGE="@earendil-works/pi-coding-agent"
OLD_PI_PACKAGE="@mariozechner/pi-coding-agent"

ensure_user_file_line "$TARGET_USER" "$TARGET_HOME/.profile" 'export PATH="$HOME/.local/bin:$PATH"'
ensure_user_file_line "$TARGET_USER" "$TARGET_HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"'

npm_has_global() {
    run_for_user "$TARGET_USER" "npm list -g --depth=0 \"$1\" >/dev/null 2>&1"
}

npm_uninstall_global() {
    run_for_user "$TARGET_USER" "npm uninstall -g \"$1\""
}

npm_install_global() {
    run_for_user "$TARGET_USER" "npm install -g $*"
}

# ── Claude Code CLI ─────────────────────────────────────────────────
# Installed via upstream curl|bash; doesn't need Node.js pre-installed.

if is_installed_for_user "$TARGET_USER" claude; then
    log_info "claude already installed, skipping"
else
    log_info "Installing Claude Code CLI for user $TARGET_USER"
    su - "$TARGET_USER" -c 'curl -fsSL https://claude.ai/install.sh | bash'
    log_info "claude installed"
fi

if ! npm_prefix_is_nvm_for_user "$TARGET_USER"; then
    log_error "npm is not configured under nvm for $TARGET_USER; run the nodejs module before installing npm-based agents"
    exit 1
fi

# ── OpenAI Codex CLI ────────────────────────────────────────────────
# Requires Node.js — 07-nodejs.sh must have run first.

if is_installed_for_user "$TARGET_USER" codex; then
    log_info "codex already installed, skipping"
else
    log_info "Installing Codex CLI for user $TARGET_USER"
    npm_install_global @openai/codex
    log_info "codex installed"
fi

# ── pi coding agent ─────────────────────────────────────────────────
# https://pi.dev — npm package.

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
