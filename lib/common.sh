#!/bin/bash
# common.sh — Shared foundation for starter-pack scripts
# Source this from every script via:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   source "$SCRIPT_DIR/../lib/common.sh"

set -euo pipefail

# ── Distro Detection ────────────────────────────────────────────────

if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_CODENAME="${VERSION_CODENAME:-}"

    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop)
            DISTRO_FAMILY="debian"
            ;;
        arch|manjaro|endeavouros)
            DISTRO_FAMILY="arch"
            ;;
        *)
            # Fall back to ID_LIKE
            if [[ "${ID_LIKE:-}" == *debian* || "${ID_LIKE:-}" == *ubuntu* ]]; then
                DISTRO_FAMILY="debian"
            elif [[ "${ID_LIKE:-}" == *arch* ]]; then
                DISTRO_FAMILY="arch"
            else
                DISTRO_FAMILY="unknown"
            fi
            ;;
    esac
else
    DISTRO_ID="unknown"
    DISTRO_CODENAME=""
    DISTRO_FAMILY="unknown"
fi

export DISTRO_ID DISTRO_CODENAME DISTRO_FAMILY

# ── Target User ───────────────────────────────────────────────────────

TARGET_USER="${TARGET_USER:-ajt}"
TARGET_HOME="${TARGET_HOME:-/home/$TARGET_USER}"

export TARGET_USER TARGET_HOME

# ── Logging ─────────────────────────────────────────────────────────

log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# ── Guards ──────────────────────────────────────────────────────────

is_installed() {
    command -v "$1" &>/dev/null
}

run_for_user() {
    local user="$1"
    local command_text="$2"

    su - "$user" -c "
        export PATH=\"\$HOME/.local/bin:\$PATH\"
        export NVM_DIR=\"\${NVM_DIR:-\$HOME/.nvm}\"
        if [ -s \"\$NVM_DIR/nvm.sh\" ]; then
            . \"\$NVM_DIR/nvm.sh\"
            nvm use --silent default >/dev/null 2>&1 || true
        fi
        $command_text
    "
}

ensure_user_file_line() {
    local user="$1"
    local file="$2"
    local line="$3"

    mkdir -p "$(dirname "$file")"
    touch "$file"
    if ! grep -qxF "$line" "$file"; then
        printf '%s\n' "$line" >> "$file"
    fi
    chown "$user:$user" "$file"
    chmod 0644 "$file"
}

is_installed_for_user() {
    local user="$1"
    local command_name="$2"

    run_for_user "$user" "command -v \"$command_name\" >/dev/null"
}

npm_prefix_is_nvm_for_user() {
    local user="$1"

    run_for_user "$user" '
        prefix="$(npm config get prefix)"
        case "$prefix" in
            "$NVM_DIR"/versions/node/*) exit 0 ;;
            *) exit 1 ;;
        esac
    '
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}
