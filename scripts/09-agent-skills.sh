#!/bin/bash
# 09-agent-skills.sh - Clone and install private coding-agent skills

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_target_user "$TARGET_USER"
if [[ "$INVOCATION_MODE" != "target-user" ]]; then
    log_error "This script must be run as target user '$TARGET_USER'"
    exit 1
fi

AGENT_SKILLS_REPO_URL="${AGENT_SKILLS_REPO_URL:-git@github.com:andrewjamesturner0/agent-skills.git}"
AGENT_SKILLS_DIR="${AGENT_SKILLS_DIR:-$TARGET_HOME/agent-skills}"
SSH_KEY="$TARGET_HOME/.ssh/github.id_rsa"
SSH_CONFIG="$TARGET_HOME/.ssh/config"
CLAUDE_HOME="${CLAUDE_HOME:-$TARGET_HOME/.claude}"
CODEX_HOME="${CODEX_HOME:-$TARGET_HOME/.codex}"
PI_AGENT_HOME="${PI_AGENT_HOME:-$TARGET_HOME/.pi/agent}"

if [[ ! -d "$TARGET_HOME" ]]; then
    log_error "Target home does not exist: $TARGET_HOME; run the user module first"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    log_error "git is not installed for $TARGET_USER; run the packages module first"
    exit 1
fi

case "$AGENT_SKILLS_REPO_URL" in
    git@*|ssh://*)
        ;;
    *)
        log_error "Agent skills repository must use an SSH URL: $AGENT_SKILLS_REPO_URL"
        exit 1
        ;;
esac

if [[ ! -f "$SSH_KEY" ]]; then
    log_error "SSH key not found at $SSH_KEY; run the ssh module before the skills module"
    exit 1
fi

if [[ ! -f "$SSH_CONFIG" ]]; then
    log_error "SSH config not found at $SSH_CONFIG; run the ssh module before the skills module"
    exit 1
fi

GIT_SSH_COMMAND="ssh -F \"$SSH_CONFIG\" -i \"$SSH_KEY\" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"

run_agent_skills_git() {
    GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$GIT_SSH_COMMAND" git "$@"
}

if [[ -d "$AGENT_SKILLS_DIR/.git" ]]; then
    log_info "Updating agent-skills"
    run_agent_skills_git -C "$AGENT_SKILLS_DIR" remote set-url origin "$AGENT_SKILLS_REPO_URL"
    run_agent_skills_git -C "$AGENT_SKILLS_DIR" pull --ff-only
elif [[ -e "$AGENT_SKILLS_DIR" ]]; then
    log_error "Agent skills destination exists but is not a git repository: $AGENT_SKILLS_DIR"
    exit 1
else
    log_info "Cloning private agent-skills repository"
    run_agent_skills_git clone "$AGENT_SKILLS_REPO_URL" "$AGENT_SKILLS_DIR"
fi

SKILLS_SOURCE="$AGENT_SKILLS_DIR/skills"
if [[ ! -d "$SKILLS_SOURCE" ]]; then
    log_error "Agent skills source directory not found at $SKILLS_SOURCE"
    exit 1
fi

CONVENTIONS_SOURCE="$AGENT_SKILLS_DIR/conventions/global.md"
if [[ ! -f "$CONVENTIONS_SOURCE" ]]; then
    log_error "Agent skills global conventions file not found at $CONVENTIONS_SOURCE"
    exit 1
fi

backup_existing_path() {
    local label="$1"
    local target="$2"
    local timestamp backup_path suffix

    timestamp="$(date -u +%Y%m%d-%H%M%S)"
    backup_path="${target}.backup-${timestamp}"
    suffix=1
    while [[ -e "$backup_path" || -L "$backup_path" ]]; do
        backup_path="${target}.backup-${timestamp}-${suffix}"
        ((suffix += 1))
    done

    mv -- "$target" "$backup_path"
    log_info "Backed up existing $label destination to $backup_path"
}

ensure_symlink_to() {
    local label="$1"
    local source="$2"
    local target="$3"
    local current_target

    if [[ -L "$target" ]]; then
        current_target="$(readlink -- "$target")"
        if [[ "$current_target" == "$source" ]]; then
            log_info "$label already linked"
            return
        fi
    fi

    if [[ -e "$target" || -L "$target" ]]; then
        backup_existing_path "$label" "$target"
    fi

    mkdir -p "$(dirname -- "$target")"
    ln -s -- "$source" "$target"
    log_info "Linked $label: $target -> $source"
}

ensure_owned_directory() {
    local label="$1"
    local target="$2"

    if [[ -L "$target" || ( -e "$target" && ! -d "$target" ) ]]; then
        backup_existing_path "$label" "$target"
    fi

    mkdir -p "$target"
}

install_codex_skills() {
    local codex_skills_dir="$1"
    local skill_source skill_name

    ensure_owned_directory "Codex skills directory" "$codex_skills_dir"

    for skill_source in "$SKILLS_SOURCE"/*; do
        [[ -d "$skill_source" ]] || continue
        skill_name="$(basename -- "$skill_source")"
        ensure_symlink_to "Codex skill $skill_name" "$skill_source" "$codex_skills_dir/$skill_name"
    done
}

log_info "Installing global conventions for installed agents"
if command -v claude >/dev/null 2>&1; then
    ensure_symlink_to "Claude conventions" "$CONVENTIONS_SOURCE" "$CLAUDE_HOME/CLAUDE.md"
else
    log_info "claude is not installed, skipping Claude conventions"
fi

if command -v pi >/dev/null 2>&1; then
    ensure_symlink_to "pi conventions" "$CONVENTIONS_SOURCE" "$PI_AGENT_HOME/APPEND_SYSTEM.md"
else
    log_info "pi is not installed, skipping pi conventions"
fi

if command -v codex >/dev/null 2>&1; then
    ensure_symlink_to "Codex conventions" "$CONVENTIONS_SOURCE" "$CODEX_HOME/AGENTS.md"
else
    log_info "codex is not installed, skipping Codex conventions"
fi

log_info "Installing agent skills for installed agents"
if command -v claude >/dev/null 2>&1; then
    ensure_symlink_to "Claude skills" "$SKILLS_SOURCE" "$CLAUDE_HOME/skills"
else
    log_info "claude is not installed, skipping Claude skills"
fi

if command -v pi >/dev/null 2>&1; then
    ensure_symlink_to "pi skills" "$SKILLS_SOURCE" "$PI_AGENT_HOME/skills"
else
    log_info "pi is not installed, skipping pi skills"
fi

if command -v codex >/dev/null 2>&1; then
    install_codex_skills "$CODEX_HOME/skills"
else
    log_info "codex is not installed, skipping Codex skills"
fi

log_info "Agent skills installation complete"
