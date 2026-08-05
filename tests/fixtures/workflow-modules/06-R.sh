#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/workflow-lib.sh"

workflow_require_root
workflow_record
install -d -m 0755 /var/lib/ignition-test
touch /var/lib/ignition-test/R
printf '%s\n%s\n' '#!/bin/sh' 'exit 0' > /usr/local/bin/R
chmod 0755 /usr/local/bin/R
