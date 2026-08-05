#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/workflow-lib.sh"

workflow_require_target
workflow_record
[[ -d "$TARGET_HOME/repos/dotfiles/.git" ]]
workflow_ensure_line "$TARGET_HOME/.profile" 'export WORKFLOW_FIXTURE=ready'
