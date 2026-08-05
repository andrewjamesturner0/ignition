#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/workflow-lib.sh"

workflow_require_target
workflow_record
install -d -m 0700 "$TARGET_HOME/.ssh"
printf '%s\n' 'fixture-private-key' > "$TARGET_HOME/.ssh/github.id_rsa"
chmod 0600 "$TARGET_HOME/.ssh/github.id_rsa"
cat > "$TARGET_HOME/.ssh/config" <<'EOF'
Host workflow.test
    IdentityFile ~/.ssh/github.id_rsa
    IdentitiesOnly yes
EOF
chmod 0644 "$TARGET_HOME/.ssh/config"
