#!/bin/sh
set -eu

printf '%s|%s|%s\n' "$(id -u)" "$(id -un)" "$HOME" \
    >> /tmp/module-contract-installer.log
touch "$HOME/.dotfiles-installed"
line='export MODULE_CONTRACT_DOTFILES=ready'
grep -qxF "$line" "$HOME/.profile" 2>/dev/null || printf '%s\n' "$line" >> "$HOME/.profile"
