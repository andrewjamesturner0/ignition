#!/bin/bash
# 04-repos.sh - Clone repos from repos.txt

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_target_user "$TARGET_USER"
if [[ "$INVOCATION_MODE" != "target-user" ]]; then
    log_error "This script must be run as target user '$TARGET_USER'"
    exit 1
fi

REPOS_DIR="$TARGET_HOME/repos"
REPOS_FILE="$SCRIPT_DIR/../repos.txt"

if [[ ! -f "$REPOS_FILE" ]]; then
    log_error "repos.txt not found at $REPOS_FILE"
    exit 1
fi

mkdir -p "$REPOS_DIR"

while IFS= read -r url || [[ -n "$url" ]]; do
    # Skip empty lines and comments
    [[ -z "$url" || "$url" == \#* ]] && continue

    # Extract repo name from URL
    name="$(basename "$url" .git)"
    target="$REPOS_DIR/$name"

    if [[ -d "$target/.git" ]]; then
        log_info "Updating $name"
        if ! git -C "$target" remote get-url origin &>/dev/null; then
            log_info "Adding origin for $name"
            git -C "$target" remote add origin "$url"
        elif [[ "$(git -C "$target" remote get-url origin)" != "$url" ]]; then
            log_info "Repairing origin for $name"
            git -C "$target" remote set-url origin "$url"
        fi
        git -C "$target" pull --ff-only || log_warn "Failed to fast-forward $name"
    else
        log_info "Cloning $name"
        git clone "$url" "$target"
    fi
done < "$REPOS_FILE"

log_info "Repos setup complete"
