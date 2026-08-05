#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/workflow-lib.sh"

workflow_require_target
workflow_record
node_dir="$TARGET_HOME/.nvm/versions/node/v24.0.0/bin"
mkdir -p "$node_dir"

cat > "$node_dir/node" <<'EOF'
#!/bin/sh
printf '%s\n' 'v24.0.0'
EOF
cat > "$node_dir/npm" <<EOF
#!/bin/sh
if [ "\${1:-}" = config ] && [ "\${2:-}" = get ] && [ "\${3:-}" = prefix ]; then
    printf '%s\n' '$TARGET_HOME/.nvm/versions/node/v24.0.0'
fi
EOF
chmod 0755 "$node_dir/node" "$node_dir/npm"

mkdir -p "$TARGET_HOME/.nvm"
cat > "$TARGET_HOME/.nvm/nvm.sh" <<'EOF'
nvm() {
    case "${1:-}" in
        use) PATH="$NVM_DIR/versions/node/v24.0.0/bin:$PATH"; export PATH ;;
        *) return 0 ;;
    esac
}
PATH="$NVM_DIR/versions/node/v24.0.0/bin:$PATH"
export PATH
EOF
workflow_ensure_line "$TARGET_HOME/.profile" 'export NVM_DIR="$HOME/.nvm"'
workflow_ensure_line "$TARGET_HOME/.profile" '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
