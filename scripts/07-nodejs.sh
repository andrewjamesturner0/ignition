#!/bin/bash
# 07-nodejs.sh — Install Node.js, npm, and nvm
# Node and npm are installed under nvm for the target user.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

NODE_MAJOR="${NODE_MAJOR:-24}"
NVM_VERSION="v0.40.4"

case "$DISTRO_FAMILY" in
    debian)
        log_info "Installing nvm prerequisites via apt"
        apt install -y ca-certificates curl git xz-utils
        ;;
    arch)
        log_info "Installing nvm prerequisites via pacman"
        pacman -S --noconfirm --needed curl git xz
        ;;
    *)
        log_error "Unsupported distro family: $DISTRO_FAMILY"
        exit 1
        ;;
esac

# ── nvm for the user ────────────────────────────────────────────────

log_info "Installing nvm $NVM_VERSION for user $TARGET_USER"

NVM_DIR="$TARGET_HOME/.nvm"

ensure_user_file_line "$TARGET_USER" "$TARGET_HOME/.profile" 'export PATH="$HOME/.local/bin:$PATH"'
ensure_user_file_line "$TARGET_USER" "$TARGET_HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"'

# Install nvm as the target user (only if not already present)
if run_for_user "$TARGET_USER" "[ -s '$NVM_DIR/nvm.sh' ]"; then
    log_info "nvm already installed, skipping"
else
    su - "$TARGET_USER" -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash"
fi

log_info "Installing Node.js $NODE_MAJOR under nvm for user $TARGET_USER"

run_for_user "$TARGET_USER" "
    nvm install $NODE_MAJOR
    nvm alias default $NODE_MAJOR
    nvm use --silent default
    npm config delete prefix >/dev/null 2>&1 || true

    prefix=\"\$(npm config get prefix)\"
    case \"\$prefix\" in
        \"\$NVM_DIR\"/versions/node/*) ;;
        *)
            echo \"npm prefix is outside nvm: \$prefix\" >&2
            exit 1
            ;;
    esac
"

log_info "user node: $(run_for_user "$TARGET_USER" 'node --version' 2>/dev/null || echo 'not found')"
log_info "user npm:  $(run_for_user "$TARGET_USER" 'npm --version' 2>/dev/null || echo 'not found')"

log_info "Node.js + npm + nvm installation complete"
