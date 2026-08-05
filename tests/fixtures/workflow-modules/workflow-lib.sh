#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

workflow_record() {
    printf '%s|%s|%s|%s|%s\n' \
        "${IGNITION_MODULE_NAME:-unknown}" "$(id -u)" "$(id -un)" "$HOME" \
        "${INVOCATION_MODE:-unknown}" >> /tmp/workflow-modules.log
}

workflow_require_root() {
    [[ "$(id -u)" -eq 0 ]]
}

workflow_require_target() {
    [[ "$(id -un)" == "$TARGET_USER" ]]
    [[ "$HOME" == "$TARGET_HOME" ]]
    [[ "${INVOCATION_MODE:-}" == "target-user" ]]
}

workflow_ensure_line() {
    local file="$1"
    local line="$2"

    mkdir -p "$(dirname "$file")"
    touch "$file"
    grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}
