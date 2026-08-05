#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/workflow-lib.sh"

if [[ "${1:-}" == "--check" ]]; then
    [[ $# -eq 1 && -f /var/lib/ignition-test/packages ]]
    exit
fi
[[ $# -eq 0 ]]
workflow_require_root
workflow_record
install -d -m 0755 /var/lib/ignition-test
touch /var/lib/ignition-test/packages
for command_name in vim tmux python3; do
    command_path="/usr/local/bin/$command_name"
    printf '%s\n%s\n' '#!/bin/sh' 'exit 0' > "$command_path"
    chmod 0755 "$command_path"
done
