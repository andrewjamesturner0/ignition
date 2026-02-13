#!/bin/bash
# 04-repos.sh — Clone repos from repos.txt

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

USERNAME="ajt"
HOME_DIR="/home/$USERNAME"
REPOS_DIR="$HOME_DIR/repos"
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
        git -C "$target" pull --ff-only || log_warn "Failed to fast-forward $name"
    else
        log_info "Cloning $name"
        git clone "$url" "$target"
    fi
done < "$REPOS_FILE"

# Fix ownership if running as root
if [[ $EUID -eq 0 ]]; then
    chown -R "$USERNAME:$USERNAME" "$REPOS_DIR"
fi

log_info "Repos setup complete"
