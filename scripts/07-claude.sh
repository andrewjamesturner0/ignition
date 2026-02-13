#!/bin/bash
# 07-claude.sh — Install Claude Code CLI via npm

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

if ! is_installed node; then
    log_error "Node.js is not installed; run 02-packages.sh first"
    exit 1
fi

if ! is_installed npm; then
    log_error "npm is not installed; run 02-packages.sh first"
    exit 1
fi

log_info "Installing Claude Code CLI"
npm install -g @anthropic-ai/claude-code

log_info "Claude Code CLI installed"
