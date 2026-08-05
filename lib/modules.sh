#!/bin/bash
# Module metadata and component-selection helpers for setup.sh.

MODULE_NAMES=(user packages ssh repos dotfiles R nodejs agents skills)
MODULE_SCRIPTS=(
    01-user.sh
    02-packages.sh
    03-ssh.sh
    04-repos.sh
    05-dotfiles.sh
    06-R.sh
    07-nodejs.sh
    08-agents.sh
    09-agent-skills.sh
)
MODULE_DESCS=(
    "Create target user"
    "Install development packages"
    "Install SSH key and config"
    "Clone repositories"
    "Install dotfiles"
    "Install R and tidyverse"
    "Install Node.js, npm, and nvm"
    "Install coding agents"
    "Install private agent skills"
)
MODULE_DEFAULT=(on on on on on off on on on)
MODULE_SCOPES=(system system user user user system mixed user user)
MODULE_SYSTEM_SCRIPTS=("" "" "" "" "" "" 07-nodejs-system.sh "" "")

declare -A MODULE_DEPENDENCIES=(
    [user]=""
    [packages]=""
    [ssh]="user packages"
    [repos]="user packages"
    [dotfiles]="repos"
    [R]=""
    [nodejs]="user packages"
    [agents]="nodejs"
    [skills]="ssh"
)

module_exists() {
    local wanted="$1"
    local name

    for name in "${MODULE_NAMES[@]}"; do
        [[ "$name" == "$wanted" ]] && return 0
    done
    return 1
}

module_depends_on() {
    local module="$1"
    local wanted="$2"
    local dependency

    for dependency in ${MODULE_DEPENDENCIES[$module]:-}; do
        if [[ "$dependency" == "$wanted" ]] || module_depends_on "$dependency" "$wanted"; then
            return 0
        fi
    done
    return 1
}

select_module_dependencies() {
    local module="$1"
    local explain="${2:-no}"
    local dependency

    for dependency in ${MODULE_DEPENDENCIES[$module]:-}; do
        if [[ "${SELECTED[$dependency]:-0}" != "1" ]]; then
            SELECTED[$dependency]=1
            AUTO_SELECTED[$dependency]=1
            if [[ "$explain" == "yes" ]]; then
                echo "  Added $dependency because $module requires it."
            fi
        fi
        select_module_dependencies "$dependency" "$explain"
    done
}

select_all_dependencies() {
    local explain="${1:-no}"
    local module

    for module in "${MODULE_NAMES[@]}"; do
        if [[ "${SELECTED[$module]:-0}" == "1" ]]; then
            select_module_dependencies "$module" "$explain"
        fi
    done
}

selected_dependent_for() {
    local prerequisite="$1"
    local module

    for module in "${MODULE_NAMES[@]}"; do
        if [[ "${SELECTED[$module]:-0}" == "1" ]] \
            && [[ "$module" != "$prerequisite" ]] \
            && module_depends_on "$module" "$prerequisite"; then
            printf '%s\n' "$module"
            return 0
        fi
    done
    return 1
}

validate_selected_dependencies() {
    local module dependency

    for module in "${MODULE_NAMES[@]}"; do
        [[ "${SELECTED[$module]:-0}" == "1" ]] || continue
        for dependency in ${MODULE_DEPENDENCIES[$module]:-}; do
            if [[ "${SELECTED[$dependency]:-0}" != "1" ]]; then
                log_error "Cannot select $module while skipping required component $dependency"
                return 1
            fi
        done
    done
}
