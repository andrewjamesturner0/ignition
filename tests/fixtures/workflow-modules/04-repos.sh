#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/workflow-lib.sh"

workflow_require_target
workflow_record
mkdir -p "$TARGET_HOME/repos"

while IFS= read -r url || [[ -n "$url" ]]; do
    [[ -z "$url" || "$url" == \#* ]] && continue
    name="$(basename "$url" .git)"
    target="$TARGET_HOME/repos/$name"
    if [[ -d "$target/.git" ]]; then
        git -C "$target" pull --ff-only
    else
        git clone "$url" "$target"
    fi
done < "$SCRIPT_DIR/../repos.txt"
