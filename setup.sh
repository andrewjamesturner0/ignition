#!/bin/bash
# Main entry point for Ignition.
# Run as root for a new system, or run ./setup.sh as the target user later.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/modules.sh"

usage() {
    cat <<EOF
Usage: ./setup.sh [--all | --skip=module1,module2]

Run as root for the first bootstrap. On later runs, run this command as
$TARGET_USER without sudo; Ignition will request sudo only for selected system work.

Modules: ${MODULE_NAMES[*]}

Options:
  --all                 Select every component, including R.
  --skip=name1,name2    Select everything except the named components.
  -h, --help            Show this help.
EOF
}

shell_quote() {
    printf '%q' "$1"
}

detect_invocation_mode

IGNITION_REPO_URL="${IGNITION_REPO_URL:-git@github.com:andrewjamesturner0/ignition.git}"
case "$IGNITION_REPO_URL" in
    git@*|ssh://*)
        ;;
    *)
        log_error "Ignition repository must use an SSH URL: $IGNITION_REPO_URL"
        exit 1
        ;;
esac
export IGNITION_REPO_URL

MODE="interactive"
SKIP=""
SELECTION_FLAG=""
for arg in "$@"; do
    case "$arg" in
        --all)
            if [[ -n "$SELECTION_FLAG" ]]; then
                log_error "Use only one of --all or --skip"
                exit 1
            fi
            SELECTION_FLAG="--all"
            MODE="all"
            ;;
        --skip=*)
            if [[ -n "$SELECTION_FLAG" ]]; then
                log_error "Use only one of --all or --skip"
                exit 1
            fi
            SELECTION_FLAG="--skip"
            MODE="skip"
            SKIP="${arg#--skip=}"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown argument: $arg"
            usage >&2
            exit 1
            ;;
    esac
done

declare -A SELECTED
declare -A AUTO_SELECTED

initialise_selection() {
    local value="$1"
    local name

    for name in "${MODULE_NAMES[@]}"; do
        SELECTED[$name]="$value"
        AUTO_SELECTED[$name]=0
    done
}

initialise_defaults() {
    local i name

    for i in "${!MODULE_NAMES[@]}"; do
        name="${MODULE_NAMES[$i]}"
        if [[ "${MODULE_DEFAULT[$i]}" == "on" ]]; then
            SELECTED[$name]=1
        else
            SELECTED[$name]=0
        fi
        AUTO_SELECTED[$name]=0
    done
}

parse_skip_list() {
    local item
    local -a requested=()

    if [[ -z "$SKIP" ]]; then
        log_error "--skip requires at least one module name"
        return 1
    fi
    IFS=',' read -r -a requested <<< "$SKIP"
    for item in "${requested[@]}"; do
        if [[ -z "$item" ]] || ! module_exists "$item"; then
            log_error "Unknown module in --skip: ${item:-<empty>}"
            return 1
        fi
        SELECTED[$item]=0
    done
}

show_selection() {
    local i name mark

    for i in "${!MODULE_NAMES[@]}"; do
        name="${MODULE_NAMES[$i]}"
        if [[ "${SELECTED[$name]}" == "1" ]]; then
            mark="*"
        else
            mark=" "
        fi
        printf "  %d) [%s] %-12s %s\n" "$((i + 1))" "$mark" "$name" "${MODULE_DESCS[$i]}"
    done
}

interactive_selection() {
    local choice idx name dependent

    if [[ ! -t 0 || ! -t 1 ]]; then
        log_error "Interactive component selection requires a terminal; use --all or --skip"
        return 1
    fi

    initialise_defaults
    echo
    echo "+------------------------------------------+"
    echo "|  Ignition - select components to install |"
    echo "+------------------------------------------+"
    echo
    echo "Toggle components with their number, then press Enter to proceed."
    echo "Components marked [*] will be installed."
    echo

    while true; do
        show_selection
        echo
        printf "  a) Select all    n) Select none    Enter) Confirm\n\n"
        if ! read -rp "  > " choice; then
            log_error "Component selection ended before confirmation"
            return 1
        fi

        case "$choice" in
            "")
                break
                ;;
            a|A)
                initialise_selection 1
                ;;
            n|N)
                initialise_selection 0
                ;;
            *[!0-9]*|0|"")
                echo "  Invalid selection."
                ;;
            *)
                idx=$((choice - 1))
                if ((idx < 0 || idx >= ${#MODULE_NAMES[@]})); then
                    echo "  Invalid selection."
                else
                    name="${MODULE_NAMES[$idx]}"
                    if [[ "${SELECTED[$name]}" == "1" ]]; then
                        if dependent="$(selected_dependent_for "$name")"; then
                            echo "  Cannot deselect $name because $dependent requires it."
                        else
                            SELECTED[$name]=0
                            AUTO_SELECTED[$name]=0
                        fi
                    else
                        SELECTED[$name]=1
                        AUTO_SELECTED[$name]=0
                        select_module_dependencies "$name" yes
                    fi
                fi
                ;;
        esac
        echo
    done
}

case "$MODE" in
    interactive)
        interactive_selection
        ;;
    all)
        initialise_selection 1
        ;;
    skip)
        initialise_selection 1
        parse_skip_list
        ;;
esac

if [[ "$MODE" == "interactive" ]]; then
    select_all_dependencies yes
fi
validate_selected_dependencies

if [[ "${SELECTED[nodejs]:-0}" == "1" && ! "${NODE_MAJOR:-24}" =~ ^[0-9]+$ ]]; then
    log_error "NODE_MAJOR must contain decimal digits only"
    exit 1
fi

if [[ "$INVOCATION_MODE" == "root-first" && "${SELECTED[user]:-0}" != "1" ]] \
    && ! id "$TARGET_USER" &>/dev/null; then
    log_error "Target user $TARGET_USER does not exist and the user component is skipped"
    exit 1
fi

selected_list=""
for name in "${MODULE_NAMES[@]}"; do
    [[ "${SELECTED[$name]}" == "1" ]] && selected_list+="$name "
done
log_info "Selected components: ${selected_list:-none}"
log_info "Detected distro: $DISTRO_ID (family=$DISTRO_FAMILY, codename=${DISTRO_CODENAME:-n/a})"
log_info "Invocation mode: $INVOCATION_MODE (user=$INVOCATION_USER, uid=$INVOCATION_UID)"

tree_owned_by_target() {
    local path="$1"
    [[ -e "$path" ]] || return 1
    [[ -z "$(find "$path" -xdev ! -user "$TARGET_USER" -print -quit)" ]]
}

module_is_satisfied() {
    local name="$1"

    case "$name" in
        user)
            id "$TARGET_USER" &>/dev/null
            ;;
        packages)
            packages_are_satisfied
            ;;
        ssh)
            [[ -f "$TARGET_HOME/.ssh/github.id_rsa" ]] \
                && [[ -f "$TARGET_HOME/.ssh/config" ]] \
                && [[ "$(stat -c %a "$TARGET_HOME/.ssh" 2>/dev/null)" == "700" ]] \
                && [[ "$(stat -c %a "$TARGET_HOME/.ssh/github.id_rsa" 2>/dev/null)" == "600" ]] \
                && [[ "$(stat -c %a "$TARGET_HOME/.ssh/config" 2>/dev/null)" == "644" ]] \
                && tree_owned_by_target "$TARGET_HOME/.ssh"
            ;;
        repos)
            repositories_are_satisfied
            ;;
        nodejs)
            is_installed_for_user "$TARGET_USER" node \
                && is_installed_for_user "$TARGET_USER" npm \
                && npm_prefix_is_nvm_for_user "$TARGET_USER" \
                && run_for_user "$TARGET_USER" "node --version | grep -q $(shell_quote "^v${NODE_MAJOR:-24}\\.")"
            ;;
        *)
            return 1
            ;;
    esac
}

packages_are_satisfied() {
    bash "$TARGET_CHECKOUT/scripts/02-packages.sh" --check
}

repositories_are_satisfied() {
    local repos_file="$TARGET_CHECKOUT/repos.txt"
    local url name target

    [[ -f "$repos_file" ]] || return 1
    while IFS= read -r url || [[ -n "$url" ]]; do
        [[ -z "$url" || "$url" == \#* ]] && continue
        name="$(basename "$url" .git)"
        target="$TARGET_HOME/repos/$name"
        [[ -d "$target/.git" ]] || return 1
        run_for_user "$TARGET_USER" "test \"\$(git -C $(shell_quote "$target") remote get-url origin)\" = $(shell_quote "$url")" || return 1
    done < "$repos_file"
}

should_run_module() {
    local name="$1"

    if [[ "${SELECTED[$name]:-0}" != "1" ]]; then
        log_warn "Skipping $name"
        return 1
    fi
    if [[ "${AUTO_SELECTED[$name]:-0}" == "1" ]] && module_is_satisfied "$name"; then
        log_info "Prerequisite $name is already satisfied"
        return 1
    fi
    return 0
}

validate_checkout_destination() {
    local destination="$1"

    case "$destination" in
        "$TARGET_HOME/ignition"|"$TARGET_HOME/Dev/ignition")
            ;;
        *)
            log_error "IGNITION_DIR must be $TARGET_HOME/ignition or $TARGET_HOME/Dev/ignition"
            return 1
            ;;
    esac
}

root_checkout_can_resume() {
    local destination="$1"
    local branch="$2"
    local source_commit target_commit target_branch target_origin quoted_destination

    [[ -d "$destination/.git" && ! -L "$destination" ]] || return 1
    tree_owned_by_target "$destination" || return 1

    quoted_destination="$(shell_quote "$destination")"
    source_commit="$(git -C "$SCRIPT_DIR" rev-parse "$branch")"
    target_commit="$(run_for_user "$TARGET_USER" "git -C $quoted_destination rev-parse HEAD")" || return 1
    target_branch="$(run_for_user "$TARGET_USER" "git -C $quoted_destination symbolic-ref --quiet --short HEAD")" || return 1
    target_origin="$(run_for_user "$TARGET_USER" "git -C $quoted_destination remote get-url origin")" || return 1

    [[ "$target_commit" == "$source_commit" && "$target_branch" == "$branch" ]] || return 1
    case "$target_origin" in
        "$IGNITION_REPO_URL")
            ;;
        /tmp/ignition-transfer.*/ignition.bundle)
            run_for_user "$TARGET_USER" "git -C $quoted_destination remote set-url origin $(shell_quote "$IGNITION_REPO_URL")"
            ;;
        *)
            return 1
            ;;
    esac
}

preflight_root_checkout() {
    local destination branch

    [[ "$INVOCATION_MODE" == "root-first" ]] || return 0
    destination="${IGNITION_DIR:-$TARGET_HOME/ignition}"
    validate_checkout_destination "$destination"

    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        log_error "Bootstrap source is not a Git worktree: $SCRIPT_DIR"
        return 1
    fi
    branch="$(git -C "$SCRIPT_DIR" symbolic-ref --quiet --short HEAD || true)"
    if [[ -z "$branch" ]]; then
        log_error "Bootstrap source must have a checked-out branch before it can be transferred"
        return 1
    fi
    if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]]; then
        log_error "Bootstrap source has uncommitted changes; commit or remove them before root-first setup"
        return 1
    fi

    if [[ -e "$destination" || -L "$destination" ]]; then
        require_target_user "$TARGET_USER" || return 1
        if ! root_checkout_can_resume "$destination" "$branch"; then
            log_error "Ignition destination exists but is not the matching target-owned checkout: $destination"
            return 1
        fi
    fi
}

seed_target_checkout() {
    local destination parent transfer_dir bundle branch quoted_bundle quoted_destination quoted_parent

    require_target_user "$TARGET_USER"
    destination="${IGNITION_DIR:-$TARGET_HOME/ignition}"
    validate_checkout_destination "$destination"

    branch="$(git -C "$SCRIPT_DIR" symbolic-ref --quiet --short HEAD || true)"

    if [[ -e "$destination" || -L "$destination" ]]; then
        root_checkout_can_resume "$destination" "$branch"
        TARGET_CHECKOUT="$destination"
        export TARGET_CHECKOUT
        log_info "Reusing target-user checkout at $TARGET_CHECKOUT"
        return 0
    fi

    transfer_dir="$(mktemp -d /tmp/ignition-transfer.XXXXXX)"
    IGNITION_TRANSFER_DIR="$transfer_dir"
    trap cleanup_transfer EXIT
    bundle="$transfer_dir/ignition.bundle"
    git -C "$SCRIPT_DIR" bundle create "$bundle" "$branch"
    chmod 0700 "$transfer_dir"
    chmod 0600 "$bundle"
    chown "$PASSWD_UID:$PASSWD_GID" "$bundle"
    chown "$PASSWD_UID:$PASSWD_GID" "$transfer_dir"

    parent="$(dirname "$destination")"
    quoted_parent="$(shell_quote "$parent")"
    quoted_bundle="$(shell_quote "$bundle")"
    quoted_destination="$(shell_quote "$destination")"
    run_for_user "$TARGET_USER" "mkdir -p -- $quoted_parent"
    run_for_user "$TARGET_USER" "git clone --branch $(shell_quote "$branch") -- $quoted_bundle $quoted_destination"
    run_for_user "$TARGET_USER" "git -C $quoted_destination remote set-url origin $(shell_quote "$IGNITION_REPO_URL")"

    TARGET_CHECKOUT="$destination"
    export TARGET_CHECKOUT
    cleanup_transfer
    trap - EXIT
    log_info "Created target-user checkout at $TARGET_CHECKOUT"
}

cleanup_transfer() {
    if [[ -n "${IGNITION_TRANSFER_DIR:-}" && -d "$IGNITION_TRANSFER_DIR" ]]; then
        rm -rf -- "$IGNITION_TRANSFER_DIR"
        IGNITION_TRANSFER_DIR=""
    fi
}

prepare_target_checkout() {
    if [[ "$INVOCATION_MODE" == "root-first" ]]; then
        seed_target_checkout
    else
        require_target_user "$TARGET_USER"
        TARGET_CHECKOUT="$SCRIPT_DIR"
        if [[ "$(stat -c %u "$TARGET_CHECKOUT")" != "$(id -u "$TARGET_USER")" ]]; then
            log_error "Ignition checkout is not owned by $TARGET_USER: $TARGET_CHECKOUT"
            return 1
        fi
        export TARGET_CHECKOUT
        log_info "Using target-user checkout at $TARGET_CHECKOUT"
    fi
}

run_system_module_script() {
    local name="$1"
    local script="$2"
    local source_root="$3"

    log_info "Running $name as root (system scope)"
    run_as_root env \
        TARGET_USER="$TARGET_USER" \
        TARGET_HOME="$TARGET_HOME" \
        IGNITION_MODULE_NAME="$name" \
        bash -c 'printf "[INFO]  Module %s effective user=%s uid=%s\n" "$IGNITION_MODULE_NAME" "$(id -un)" "$(id -u)"; exec bash "$1"' \
        ignition-module "$source_root/scripts/$script"
}

run_user_module_script() {
    local name="$1"
    local script="$2"
    local command_text

    command_text="export TARGET_USER=$(shell_quote "$TARGET_USER") TARGET_HOME=$(shell_quote "$TARGET_HOME")"
    command_text+=" IGNITION_MODULE_NAME=$(shell_quote "$name")"
    for variable in AGENT_SKILLS_REPO_URL AGENT_SKILLS_DIR CLAUDE_HOME CODEX_HOME PI_AGENT_HOME NODE_MAJOR NVM_VERSION; do
        if [[ -n "${!variable:-}" ]]; then
            command_text+=" $variable=$(shell_quote "${!variable}")"
        fi
    done
    command_text+="; printf '[INFO]  Module %s effective user=%s uid=%s\\n' \"\$IGNITION_MODULE_NAME\" \"\$(id -un)\" \"\$(id -u)\""
    command_text+="; bash $(shell_quote "$TARGET_CHECKOUT/scripts/$script")"

    log_info "Running $name as $TARGET_USER (user scope)"
    run_for_user "$TARGET_USER" "$command_text"
}

run_module() {
    local index="$1"
    local name="${MODULE_NAMES[$index]}"
    local script="${MODULE_SCRIPTS[$index]}"
    local scope="${MODULE_SCOPES[$index]}"
    local system_script="${MODULE_SYSTEM_SCRIPTS[$index]}"

    should_run_module "$name" || return 0
    log_info "------ Running: $name ------"

    case "$scope" in
        system)
            run_system_module_script "$name" "$script" "$SCRIPT_DIR"
            ;;
        user)
            run_user_module_script "$name" "$script"
            ;;
        mixed)
            run_system_module_script "$name prerequisites" "$system_script" "$SCRIPT_DIR"
            run_user_module_script "$name" "$script"
            ;;
        *)
            log_error "Unknown module scope for $name: $scope"
            return 1
            ;;
    esac
}

TARGET_CHECKOUT=""
preflight_root_checkout
for i in "${!MODULE_NAMES[@]}"; do
    run_module "$i"
    if [[ "${MODULE_NAMES[$i]}" == "user" ]]; then
        prepare_target_checkout
    fi
done

log_info "------ Verification ------"

PASS=0
FAIL=0

check() {
    local label="$1"
    shift
    if "$@" &>/dev/null; then
        echo "[OK]   $label"
        ((++PASS))
    else
        echo "[FAIL] $label"
        ((++FAIL))
    fi
}

link_points_to() {
    local path="$1"
    local target="$2"
    [[ -L "$path" && "$(readlink -- "$path")" == "$target" ]]
}

skills_linked_into_dir() {
    local source_dir="$1"
    local target_dir="$2"
    local source skill_name

    [[ -d "$source_dir" && -d "$target_dir" ]] || return 1
    for source in "$source_dir"/*; do
        [[ -d "$source" ]] || continue
        skill_name="$(basename -- "$source")"
        link_points_to "$target_dir/$skill_name" "$source" || return 1
    done
}

check "User $TARGET_USER exists" id "$TARGET_USER"
check "Target checkout is a Git worktree" run_for_user "$TARGET_USER" "git -C $(shell_quote "$TARGET_CHECKOUT") status"
check "Target checkout origin uses SSH" run_for_user "$TARGET_USER" "test \"\$(git -C $(shell_quote "$TARGET_CHECKOUT") remote get-url origin)\" = $(shell_quote "$IGNITION_REPO_URL")"
check "Target checkout belongs to $TARGET_USER" tree_owned_by_target "$TARGET_CHECKOUT"

if [[ "${SELECTED[packages]:-0}" == "1" ]]; then
    check "git installed" command -v git
    check "vim installed" command -v vim
    check "tmux installed" command -v tmux
    check "python3 installed" command -v python3
fi

if [[ "${SELECTED[nodejs]:-0}" == "1" ]]; then
    check "node installed for $TARGET_USER" is_installed_for_user "$TARGET_USER" node
    check "npm installed for $TARGET_USER" is_installed_for_user "$TARGET_USER" npm
    check "npm prefix under nvm" npm_prefix_is_nvm_for_user "$TARGET_USER"
fi

if [[ "${SELECTED[ssh]:-0}" == "1" ]]; then
    check "SSH directory belongs to $TARGET_USER" tree_owned_by_target "$TARGET_HOME/.ssh"
    check "SSH key mode is 600" test "$(stat -c %a "$TARGET_HOME/.ssh/github.id_rsa" 2>/dev/null)" = "600"
    check "SSH config mode is 644" test "$(stat -c %a "$TARGET_HOME/.ssh/config" 2>/dev/null)" = "644"
fi

if [[ "${SELECTED[R]:-0}" == "1" ]]; then
    check "R installed" command -v R
fi

if [[ "${SELECTED[agents]:-0}" == "1" ]]; then
    check "claude installed" is_installed_for_user "$TARGET_USER" claude
    check "codex installed" is_installed_for_user "$TARGET_USER" codex
    check "pi installed" is_installed_for_user "$TARGET_USER" pi
fi

if [[ "${SELECTED[skills]:-0}" == "1" ]]; then
    agent_skills_dir="${AGENT_SKILLS_DIR:-$TARGET_HOME/agent-skills}"
    claude_home="${CLAUDE_HOME:-$TARGET_HOME/.claude}"
    codex_home="${CODEX_HOME:-$TARGET_HOME/.codex}"
    pi_agent_home="${PI_AGENT_HOME:-$TARGET_HOME/.pi/agent}"
    check "agent-skills repository cloned" test -d "$agent_skills_dir/.git"
    check "agent-skills repository belongs to $TARGET_USER" tree_owned_by_target "$agent_skills_dir"

    if is_installed_for_user "$TARGET_USER" claude; then
        check "Claude skills linked" link_points_to "$claude_home/skills" "$agent_skills_dir/skills"
        check "Claude conventions linked" link_points_to "$claude_home/CLAUDE.md" "$agent_skills_dir/conventions/global.md"
    fi
    if is_installed_for_user "$TARGET_USER" pi; then
        check "pi skills linked" link_points_to "$pi_agent_home/skills" "$agent_skills_dir/skills"
        check "pi conventions linked" link_points_to "$pi_agent_home/APPEND_SYSTEM.md" "$agent_skills_dir/conventions/global.md"
    fi
    if is_installed_for_user "$TARGET_USER" codex; then
        check "Codex skills linked" skills_linked_into_dir "$agent_skills_dir/skills" "$codex_home/skills"
        check "Codex conventions linked" link_points_to "$codex_home/AGENTS.md" "$agent_skills_dir/conventions/global.md"
    fi
fi

echo
log_info "Results: $PASS passed, $FAIL failed"
((FAIL == 0))
