#!/bin/bash
# Shared foundation for Ignition scripts.
# Source this from every script via:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   source "$SCRIPT_DIR/../lib/common.sh"

set -euo pipefail

# Distro detection

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

# Target user

TARGET_USER="${TARGET_USER:-ajt}"
if [[ ${TARGET_HOME+x} ]]; then
    _TARGET_HOME_WAS_SET=1
else
    _TARGET_HOME_WAS_SET=0
    TARGET_HOME="/home/$TARGET_USER"
fi

export TARGET_USER TARGET_HOME

# Logging

log_info()  { echo "[INFO]  $*"; }
log_warn()  { echo "[WARN]  $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

# Guards and command execution

_load_passwd_record() {
    local user="$1"
    local passwd_record

    if [[ -z "$user" || "$user" == -* || "$user" == *:* || "$user" == *$'\n'* ]]; then
        return 1
    fi

    passwd_record="$(getent passwd "$user")" || return 1
    IFS=: read -r _ _ PASSWD_UID PASSWD_GID _ PASSWD_HOME PASSWD_SHELL <<< "$passwd_record"

    [[ "$PASSWD_UID" =~ ^[0-9]+$ && "$PASSWD_GID" =~ ^[0-9]+$ ]]
    [[ "$PASSWD_HOME" == /* && "$PASSWD_SHELL" == /* ]]
}

_target_settings_are_safe() {
    [[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*\$?$ ]]
    [[ "$TARGET_USER" != root ]]
    [[ "$TARGET_HOME" == /* && "$TARGET_HOME" != *:* && "$TARGET_HOME" != *$'\n'* ]]
    if ! getent passwd "$TARGET_USER" &>/dev/null; then
        [[ "$TARGET_HOME" == "/home/$TARGET_USER" ]]
    fi
}

validate_target_user() {
    local user="${1:-$TARGET_USER}"

    [[ "$user" == "$TARGET_USER" ]] || return 1
    [[ "$TARGET_USER" != root ]] || return 1
    _load_passwd_record "$user" || return 1
    [[ "$PASSWD_UID" -ne 0 && -d "$PASSWD_HOME" ]] || return 1

    if [[ $_TARGET_HOME_WAS_SET -eq 1 && "$TARGET_HOME" != "$PASSWD_HOME" ]]; then
        return 1
    fi

    TARGET_HOME="$PASSWD_HOME"
    TARGET_SHELL="$PASSWD_SHELL"
    export TARGET_HOME TARGET_SHELL
}

require_target_user() {
    local user="${1:-$TARGET_USER}"

    if ! validate_target_user "$user"; then
        log_error "Target user '$user' must exist with a valid passwd home matching TARGET_HOME"
        return 1
    fi
}

detect_invocation_mode() {
    if ! _target_settings_are_safe; then
        log_error "TARGET_USER and TARGET_HOME must name a safe non-root account and absolute home path"
        return 1
    fi

    INVOCATION_UID="$(id -u)"
    INVOCATION_USER="$(id -un)"

    if [[ "$INVOCATION_UID" -eq 0 ]]; then
        INVOCATION_MODE="root-first"
        if getent passwd "$TARGET_USER" >/dev/null; then
            require_target_user "$TARGET_USER" || return 1
        fi
    elif [[ "$INVOCATION_USER" == "$TARGET_USER" ]]; then
        INVOCATION_MODE="target-user"
        require_target_user "$TARGET_USER" || return 1
    else
        log_error "Run Ignition as root or as target user '$TARGET_USER', not '$INVOCATION_USER'"
        return 1
    fi

    export INVOCATION_UID INVOCATION_USER INVOCATION_MODE
}

_user_command_shell='\
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    . "$NVM_DIR/nvm.sh"
    nvm use --silent default >/dev/null 2>&1 || true
fi
eval "$IGNITION_USER_COMMAND"
'

run_for_user() {
    local user="$1"
    local command_text="$2"
    local user_path terminal_type gpg_tty

    if [[ "$user" != "$TARGET_USER" ]]; then
        log_error "Refusing to run a user command for '$user'; target user is '$TARGET_USER'"
        return 1
    fi
    require_target_user "$user" || return 1

    user_path="$TARGET_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games"
    terminal_type="${TERM:-dumb}"
    gpg_tty=""
    if [[ -t 0 ]]; then
        gpg_tty="$(tty)"
    fi

    if [[ "$(id -u)" -eq "$PASSWD_UID" ]]; then
        HOME="$TARGET_HOME" \
        USER="$user" \
        LOGNAME="$user" \
        SHELL="$TARGET_SHELL" \
        PATH="$user_path" \
        TERM="$terminal_type" \
        GPG_TTY="$gpg_tty" \
        IGNITION_USER_COMMAND="$command_text" \
            bash --noprofile --norc -c "$_user_command_shell"
    elif [[ "$(id -u)" -eq 0 ]]; then
        runuser -u "$user" -- env -i \
            HOME="$TARGET_HOME" \
            USER="$user" \
            LOGNAME="$user" \
            SHELL="$TARGET_SHELL" \
            PATH="$user_path" \
            TERM="$terminal_type" \
            GPG_TTY="$gpg_tty" \
            IGNITION_USER_COMMAND="$command_text" \
            bash --noprofile --norc -c "$_user_command_shell"
    else
        log_error "Only root or '$user' may run commands as '$user'"
        return 1
    fi
}

run_as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif [[ "$(id -un)" == "$TARGET_USER" ]]; then
        sudo -- "$@"
    else
        log_error "Only root or '$TARGET_USER' may run root commands"
        return 1
    fi
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

if ! detect_invocation_mode; then
    return 1 2>/dev/null || exit 1
fi
