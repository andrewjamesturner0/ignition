#!/bin/bash
# 09-agent-skills.sh - Clone and install private coding-agent skills

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

AGENT_SKILLS_REPO_URL="${AGENT_SKILLS_REPO_URL:-git@github.com:andrewjamesturner0/agent-skills.git}"
AGENT_SKILLS_DIR="${AGENT_SKILLS_DIR:-$TARGET_HOME/agent-skills}"
SSH_KEY="$TARGET_HOME/.ssh/github.id_rsa"

if [[ ! -d "$TARGET_HOME" ]]; then
    log_error "Target home does not exist: $TARGET_HOME; run the user module first"
    exit 1
fi

if ! is_installed_for_user "$TARGET_USER" git; then
    log_error "git is not installed for $TARGET_USER; run the packages module first"
    exit 1
fi

case "$AGENT_SKILLS_REPO_URL" in
    git@*|ssh://*)
        if [[ ! -f "$SSH_KEY" ]]; then
            log_error "SSH key not found at $SSH_KEY; run the ssh module before the skills module"
            exit 1
        fi
        ;;
esac

if [[ -d "$AGENT_SKILLS_DIR/.git" ]]; then
    log_info "Updating agent-skills"
    run_for_user "$TARGET_USER" "git -C \"$AGENT_SKILLS_DIR\" pull --ff-only"
elif [[ -e "$AGENT_SKILLS_DIR" ]]; then
    log_error "Agent skills destination exists but is not a git repository: $AGENT_SKILLS_DIR"
    exit 1
else
    log_info "Cloning private agent-skills repository"
    run_for_user "$TARGET_USER" "git clone \"$AGENT_SKILLS_REPO_URL\" \"$AGENT_SKILLS_DIR\""
fi

INSTALLER="$AGENT_SKILLS_DIR/scripts/install.sh"
if [[ ! -f "$INSTALLER" ]]; then
    log_error "Agent skills installer not found at $INSTALLER"
    exit 1
fi

log_info "Installing agent skills and global conventions"
run_for_user "$TARGET_USER" "bash \"$INSTALLER\" --backup"

log_info "Agent skills installation complete"
