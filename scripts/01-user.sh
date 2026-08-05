#!/bin/bash
# Create the target user with password-protected sudo privileges.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_root

STATE_DIR="/var/lib/ignition"
PENDING_MARKER="$STATE_DIR/pending-user-password"
LEGACY_WHEEL_RULE="/etc/sudoers.d/wheel-nopasswd"
ARCH_WHEEL_RULE="/etc/sudoers.d/ignition-wheel"
MARKER_VERSION="1"
MARKER_STATUS=""
MARKER_TOKEN=""
ACCOUNT_TAG=""

write_pending_marker() {
    local status="$1"
    local temporary_marker

    temporary_marker="$(mktemp "$STATE_DIR/.pending-user-password.XXXXXX")"
    printf '%s\n%s\n%s\n%s\n' \
        "$MARKER_VERSION" "$TARGET_USER" "$MARKER_TOKEN" "$status" \
        > "$temporary_marker"
    chown root:root "$temporary_marker"
    chmod 0600 "$temporary_marker"
    mv -f -- "$temporary_marker" "$PENDING_MARKER"
}

read_pending_marker() {
    local marker_version marker_user extra_line

    if [[ -L "$PENDING_MARKER" || ! -f "$PENDING_MARKER" ]]; then
        log_error "Unsafe Ignition password marker: $PENDING_MARKER must be a regular file"
        exit 1
    fi
    if [[ "$(stat -c '%u:%a' "$PENDING_MARKER")" != "0:600" ]]; then
        log_error "Unsafe Ignition password marker: $PENDING_MARKER must be owned by root with mode 0600"
        exit 1
    fi

    {
        IFS= read -r marker_version
        IFS= read -r marker_user
        IFS= read -r MARKER_TOKEN
        IFS= read -r MARKER_STATUS
        IFS= read -r extra_line || true
    } < "$PENDING_MARKER"

    if [[ "$marker_version" != "$MARKER_VERSION" ||
          "$marker_user" != "$TARGET_USER" ||
          ! "$MARKER_TOKEN" =~ ^[0-9a-f]{32}$ ||
          ! "$MARKER_STATUS" =~ ^(creating|password-set)$ ||
          -n "$extra_line" ]]; then
        log_error "Invalid Ignition password marker: $PENDING_MARKER"
        exit 1
    fi
}

ensure_arch_password_sudo() {
    local temporary_rule

    mkdir -p /etc/sudoers.d
    temporary_rule="$(mktemp /etc/sudoers.d/.ignition-wheel.XXXXXX)"
    printf '%s\n' '%wheel ALL=(ALL:ALL) ALL' > "$temporary_rule"
    chown root:root "$temporary_rule"
    chmod 0440 "$temporary_rule"
    if command -v visudo &>/dev/null; then
        visudo -cf "$temporary_rule" >/dev/null
    fi
    mv -f -- "$temporary_rule" "$ARCH_WHEEL_RULE"
}

remove_legacy_wheel_rule() {
    if [[ -L "$LEGACY_WHEEL_RULE" ]]; then
        log_warn "Not removing symlink at legacy sudoers path $LEGACY_WHEEL_RULE"
    elif [[ -f "$LEGACY_WHEEL_RULE" ]]; then
        if [[ "$(cat -- "$LEGACY_WHEEL_RULE")" == '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' ]]; then
            rm -- "$LEGACY_WHEEL_RULE"
            log_info "Removed Ignition's legacy passwordless wheel rule"
            if [[ "$DISTRO_FAMILY" == "arch" ]]; then
                ensure_arch_password_sudo
            fi
        else
            log_warn "Not removing modified legacy sudoers file $LEGACY_WHEEL_RULE"
        fi
    fi
}

remove_legacy_wheel_rule

if [[ ! -e "$PENDING_MARKER" && ! -L "$PENDING_MARKER" ]] && id "$TARGET_USER" &>/dev/null; then
    log_info "User $TARGET_USER already exists, skipping"
    exit 0
fi

if [[ -L "$STATE_DIR" || ( -e "$STATE_DIR" && ! -d "$STATE_DIR" ) ]]; then
    log_error "Unsafe Ignition state path: $STATE_DIR must be a directory"
    exit 1
fi
install -d -o root -g root -m 0700 "$STATE_DIR"

if [[ -e "$PENDING_MARKER" || -L "$PENDING_MARKER" ]]; then
    read_pending_marker
else
    MARKER_TOKEN="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
    MARKER_STATUS="creating"
    write_pending_marker "$MARKER_STATUS"
fi

ACCOUNT_TAG="Ignition-created-$MARKER_TOKEN"

if [[ "$MARKER_STATUS" == "password-set" ]]; then
    if ! id "$TARGET_USER" &>/dev/null; then
        log_error "Ignition password marker says setup completed, but user $TARGET_USER does not exist"
        exit 1
    fi
    if [[ "$(getent passwd "$TARGET_USER" | cut -d: -f5)" == "$ACCOUNT_TAG" ]]; then
        usermod -c "" "$TARGET_USER"
    fi
    rm -- "$PENDING_MARKER"
    log_info "Password setup for $TARGET_USER was already completed"
    exit 0
fi

if [[ ! -t 0 || ! -t 1 ]]; then
    log_error "An interactive terminal is required to set the password for new user $TARGET_USER"
    log_error "No account password was changed; rerun Ignition from an interactive terminal"
    exit 1
fi

if ! command -v sudo &>/dev/null; then
    log_info "Installing sudo for the new administrative user"
    case "$DISTRO_FAMILY" in
        debian)
            apt-get update
            apt-get install -y sudo
            ;;
        arch)
            pacman -S --noconfirm --needed sudo
            ;;
        *)
            log_error "Unsupported distro family: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
fi

if id "$TARGET_USER" &>/dev/null; then
    if [[ "$(getent passwd "$TARGET_USER" | cut -d: -f5)" != "$ACCOUNT_TAG" ]]; then
        log_error "Refusing to change the password for existing user $TARGET_USER: the pending marker does not match the account"
        exit 1
    fi
    log_info "Resuming password setup for Ignition-created user $TARGET_USER"
else
    log_info "Creating user $TARGET_USER"
    useradd -m -d "$TARGET_HOME" -s /bin/bash -c "$ACCOUNT_TAG" "$TARGET_USER"
fi

case "$DISTRO_FAMILY" in
    debian)
        usermod -aG sudo "$TARGET_USER"
        log_info "Added $TARGET_USER to sudo group"
        ;;
    arch)
        usermod -aG wheel "$TARGET_USER"
        ensure_arch_password_sudo
        log_info "Added $TARGET_USER to wheel group with password-protected sudo"
        ;;
    *)
        log_error "Unsupported distro family: $DISTRO_FAMILY"
        exit 1
        ;;
esac

log_info "Set a password for $TARGET_USER"
if ! passwd "$TARGET_USER"; then
    log_error "Password setup failed for $TARGET_USER; the pending marker has been kept for a retry"
    exit 1
fi

MARKER_STATUS="password-set"
write_pending_marker "$MARKER_STATUS"
usermod -c "" "$TARGET_USER"
rm -- "$PENDING_MARKER"

log_info "User $TARGET_USER created successfully with password-protected administrative access"
