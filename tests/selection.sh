#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log_error() {
    echo "$*" >&2
}

source "$repo_root/lib/modules.sh"

error_file="$(mktemp)"
trap 'rm -f -- "$error_file"' EXIT

reset_selection() {
    local name
    declare -gA SELECTED=()
    declare -gA AUTO_SELECTED=()
    for name in "${MODULE_NAMES[@]}"; do
        SELECTED[$name]=0
        AUTO_SELECTED[$name]=0
    done
}

reset_selection
SELECTED[agents]=1
select_all_dependencies no
for expected in user packages nodejs agents; do
    [[ "${SELECTED[$expected]}" == "1" ]]
done
[[ "${AUTO_SELECTED[nodejs]}" == "1" ]]
[[ "${AUTO_SELECTED[packages]}" == "1" ]]
[[ "$(selected_dependent_for packages)" == "nodejs" ]]

reset_selection
SELECTED[dotfiles]=1
SELECTED[repos]=0
if validate_selected_dependencies 2>"$error_file"; then
    echo "Dependency conflict was accepted" >&2
    exit 1
fi
grep -q "dotfiles" "$error_file"
grep -q "repos" "$error_file"

reset_selection
SELECTED[skills]=1
select_all_dependencies no
for expected in user packages ssh skills; do
    [[ "${SELECTED[$expected]}" == "1" ]]
done

echo "Selection tests passed"
