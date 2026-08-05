#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/workflow-lib.sh"

workflow_require_target
workflow_record
mkdir -p "$TARGET_HOME/.local/bin"
for command_name in claude codex pi; do
    command_path="$TARGET_HOME/.local/bin/$command_name"
    printf '%s\n%s\n' '#!/bin/sh' 'exit 0' > "$command_path"
    chmod 0755 "$command_path"
done
