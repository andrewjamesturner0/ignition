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

# ── Logging ─────────────────────────────────────────────────────────

log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# ── Guards ──────────────────────────────────────────────────────────

is_installed() {
    command -v "$1" &>/dev/null
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}
