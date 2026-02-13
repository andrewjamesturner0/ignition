#!/bin/bash
# setup.sh — Main entry point for ignition VM bootstrap
# Usage: sudo bash setup.sh [--skip=module1,module2]
#
# Modules: user, packages, ssh, repos, dotfiles, R, claude
# Example: sudo bash setup.sh --skip=R,claude

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root

# ── Parse --skip flag ───────────────────────────────────────────────

SKIP=""
for arg in "$@"; do
    case "$arg" in
        --skip=*)
            SKIP="${arg#--skip=}"
            ;;
        *)
            log_error "Unknown argument: $arg"
            echo "Usage: sudo bash setup.sh [--skip=module1,module2]"
            echo "Modules: user, packages, ssh, repos, dotfiles, R, claude"
            exit 1
            ;;
    esac
done

should_skip() {
    [[ ",$SKIP," == *",$1,"* ]]
}

# ── Distro Info ─────────────────────────────────────────────────────

log_info "Detected distro: $DISTRO_ID (family=$DISTRO_FAMILY, codename=${DISTRO_CODENAME:-n/a})"

# ── Run Modules ─────────────────────────────────────────────────────

run_module() {
    local name="$1"
    local script="$2"

    if should_skip "$name"; then
        log_warn "Skipping $name (--skip)"
        return
    fi

    log_info "────── Running: $name ──────"
    bash "$SCRIPT_DIR/scripts/$script"
}

run_module "user"     "01-user.sh"
run_module "packages" "02-packages.sh"
run_module "ssh"      "03-ssh.sh"
run_module "repos"    "04-repos.sh"
run_module "dotfiles" "05-dotfiles.sh"
run_module "R"        "06-R.sh"
run_module "claude"   "07-claude.sh"

# ── Verification ────────────────────────────────────────────────────

log_info "────── Verification ──────"

PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    if "$@" &>/dev/null; then
        echo "[OK]   $label"
        ((PASS++))
    else
        echo "[FAIL] $label"
        ((FAIL++))
    fi
}

check "User ajt exists"                          id ajt
check "git installed"                             is_installed git
check "vim installed"                             is_installed vim
check "tmux installed"                            is_installed tmux
check "python3 installed"                         is_installed python3
check "node installed"                            is_installed node
check "SSH key at /home/ajt/.ssh/github.id_rsa"  test -f /home/ajt/.ssh/github.id_rsa
check "SSH key mode 600"                          test "$(stat -c %a /home/ajt/.ssh/github.id_rsa 2>/dev/null)" = "600"
check "R installed"                               is_installed R
check "claude installed"                          is_installed claude

echo ""
log_info "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
