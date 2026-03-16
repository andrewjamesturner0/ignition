#!/bin/bash
# 07-claude.sh — Install Claude Code CLI via curl | bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

if ! is_installed curl; then
    log_error "curl is not installed; run 02-packages.sh first"
    exit 1
fi

log_info "Installing Claude Code CLI for user ajt"
su - ajt -c 'curl -fsSL https://claude.ai/install.sh | sh'

log_info "Claude Code CLI installed"
