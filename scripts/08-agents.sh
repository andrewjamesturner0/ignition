#!/bin/bash
# 08-agents.sh — Install coding agents: Claude Code, Codex CLI, and pi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

AGENT_USER="ajt"

# ── Helpers ─────────────────────────────────────────────────────────

agent_skip()  { log_info "$1 already installed, skipping"; }
agent_done()  { log_info "$1 installed"; }

# ── Claude Code CLI ─────────────────────────────────────────────────
# Installed via upstream curl|bash; doesn't need Node.js pre-installed.

if is_installed claude; then
    agent_skip "claude"
else
    log_info "Installing Claude Code CLI for user $AGENT_USER"
    su - "$AGENT_USER" -c 'curl -fsSL https://claude.ai/install.sh | bash'
    agent_done "claude"
fi

# ── OpenAI Codex CLI ────────────────────────────────────────────────
# Requires Node.js — 07-nodejs.sh must have run first.

if is_installed codex; then
    agent_skip "codex"
else
    log_info "Installing Codex CLI"
    npm install -g @openai/codex
    agent_done "codex"
fi

# ── pi coding agent ─────────────────────────────────────────────────
# https://pi.dev — npm package.

if is_installed pi; then
    agent_skip "pi"
else
    log_info "Installing pi coding agent"
    npm install -g @mariozechner/pi-coding-agent
    agent_done "pi"
fi

log_info "Coding agents installation complete"
