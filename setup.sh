#!/bin/bash
# setup.sh — Main entry point for ignition VM bootstrap
# Usage: sudo bash setup.sh [--all | --skip=module1,module2]
#
# Modules: user, packages, ssh, repos, dotfiles, R, nodejs, agents
# Examples:
#   sudo bash setup.sh              # interactive component selection
#   sudo bash setup.sh --all        # install everything
#   sudo bash setup.sh --skip=R     # install everything except R

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_root

# ── Module definitions ──────────────────────────────────────────────

MODULE_NAMES=(  user          packages              ssh             repos                dotfiles          R                     nodejs              agents                      )
MODULE_SCRIPTS=(01-user.sh    02-packages.sh        03-ssh.sh       04-repos.sh          05-dotfiles.sh    06-R.sh               07-nodejs.sh        08-agents.sh                )
MODULE_DESCS=(  "Create user" "Install dev packages" "SSH key setup" "Clone repositories" "Install dotfiles" "R + tidyverse"      "Node.js + npm + nvm" "Coding agents"            )
MODULE_DEFAULT=(on            on                    on              on                   on                off                   on                  on                          )

# ── Parse flags ─────────────────────────────────────────────────────

MODE="interactive"
SKIP=""
for arg in "$@"; do
    case "$arg" in
        --all)
            MODE="all"
            ;;
        --skip=*)
            MODE="skip"
            SKIP="${arg#--skip=}"
            ;;
        *)
            log_error "Unknown argument: $arg"
            echo "Usage: sudo bash setup.sh [--all | --skip=module1,module2]"
            log_error "Modules: ${MODULE_NAMES[*]}"
            exit 1
            ;;
    esac
done

should_skip() {
    [[ ",$SKIP," == *",$1,"* ]]
}

# ── Interactive component selection ─────────────────────────────────

declare -A SELECTED

if [[ "$MODE" == "interactive" ]]; then
    echo ""
    echo "┌──────────────────────────────────────────┐"
    echo "│  ignition — select components to install  │"
    echo "└──────────────────────────────────────────┘"
    echo ""
    echo "Toggle components with their number, then press Enter to proceed."
    echo "Components marked [*] will be installed."
    echo ""

    # initialise from defaults
    for i in "${!MODULE_NAMES[@]}"; do
        [[ "${MODULE_DEFAULT[$i]}" == "on" ]] && SELECTED[${MODULE_NAMES[$i]}]=1 || SELECTED[${MODULE_NAMES[$i]}]=0
    done

    while true; do
        for i in "${!MODULE_NAMES[@]}"; do
            local_name="${MODULE_NAMES[$i]}"
            if [[ "${SELECTED[$local_name]}" == "1" ]]; then
                mark="*"
            else
                mark=" "
            fi
            printf "  %d) [%s] %-12s %s\n" "$((i+1))" "$mark" "$local_name" "${MODULE_DESCS[$i]}"
        done
        echo ""
        printf "  a) Select all    n) Select none    Enter) Confirm\n\n"
        read -rp "  > " choice

        case "$choice" in
            "")
                break
                ;;
            a|A)
                for name in "${MODULE_NAMES[@]}"; do SELECTED[$name]=1; done
                ;;
            n|N)
                for name in "${MODULE_NAMES[@]}"; do SELECTED[$name]=0; done
                ;;
            *[0-9]*)
                idx=$((choice - 1))
                if [[ $idx -ge 0 && $idx -lt ${#MODULE_NAMES[@]} ]]; then
                    name="${MODULE_NAMES[$idx]}"
                    [[ "${SELECTED[$name]}" == "1" ]] && SELECTED[$name]=0 || SELECTED[$name]=1
                else
                    echo "  Invalid selection."
                fi
                ;;
            *)
                echo "  Invalid selection."
                ;;
        esac
        echo ""
    done

    echo ""
    selected_list=""
    for name in "${MODULE_NAMES[@]}"; do
        [[ "${SELECTED[$name]}" == "1" ]] && selected_list+="$name "
    done
    log_info "Selected components: ${selected_list:-none}"
    echo ""
elif [[ "$MODE" == "all" ]]; then
    for name in "${MODULE_NAMES[@]}"; do SELECTED[$name]=1; done
else
    # --skip mode: enable all, then disable skipped
    for name in "${MODULE_NAMES[@]}"; do SELECTED[$name]=1; done
    for name in "${MODULE_NAMES[@]}"; do
        should_skip "$name" && SELECTED[$name]=0
    done
fi

# ── Distro Info ─────────────────────────────────────────────────────

log_info "Detected distro: $DISTRO_ID (family=$DISTRO_FAMILY, codename=${DISTRO_CODENAME:-n/a})"

# ── Run Modules ─────────────────────────────────────────────────────

run_module() {
    local name="$1"
    local script="$2"

    if [[ "${SELECTED[$name]:-0}" != "1" ]]; then
        log_warn "Skipping $name"
        return
    fi

    log_info "────── Running: $name ──────"
    bash "$SCRIPT_DIR/scripts/$script"
}

for i in "${!MODULE_NAMES[@]}"; do
    run_module "${MODULE_NAMES[$i]}" "${MODULE_SCRIPTS[$i]}"
done

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

if [[ "${SELECTED[packages]:-0}" == "1" ]]; then
    check "git installed"                             is_installed git
    check "vim installed"                             is_installed vim
    check "tmux installed"                            is_installed tmux
    check "python3 installed"                         is_installed python3
fi

if [[ "${SELECTED[nodejs]:-0}" == "1" ]]; then
    check "node installed"                            is_installed node
    check "npm installed"                             is_installed npm
fi

if [[ "${SELECTED[ssh]:-0}" == "1" ]]; then
    check "SSH key at /home/ajt/.ssh/github.id_rsa"  test -f /home/ajt/.ssh/github.id_rsa
    check "SSH key mode 600"                          test "$(stat -c %a /home/ajt/.ssh/github.id_rsa 2>/dev/null)" = "600"
fi

if [[ "${SELECTED[R]:-0}" == "1" ]]; then
    check "R installed"                               is_installed R
fi

if [[ "${SELECTED[agents]:-0}" == "1" ]]; then
    check "claude installed"                          is_installed claude
    check "codex installed"                           is_installed codex
    check "pi installed"                              is_installed pi
fi

echo ""
log_info "Results: $PASS passed, $FAIL failed"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
