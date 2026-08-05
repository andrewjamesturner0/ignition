#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tests/docker-integration.sh [profile]

Profiles:
  syntax                       Run shell syntax checks in Ubuntu.
  ubuntu-core                  Run core modules with live installers. Default.
  ubuntu-agents                Run agent modules with live installers.
  ubuntu-skills                Test private skills cloning through the SSH key.
  ubuntu-workflow-root         Test root-first setup and the default checkout.
  ubuntu-workflow-root-dev     Test root-first setup with IGNITION_DIR under Dev.
  ubuntu-workflow-later        Test later user/system selections and reruns.
  ubuntu-workflow-conflict     Test dependency preflight before any mutation.
  ubuntu-module-contracts      Test production SSH, repos, dotfiles, and R modules offline.

Environment:
  IMAGE           Docker image to use. Default: ubuntu:24.04
  TARGET_USER     User created inside the container. Default: testuser

Notes:
  The repo is mounted read-only and copied inside the container.
  Workflow profiles use committed fixture modules and no live installers.
  The core and agents profiles use live upstream installers.
EOF
}

profile="${1:-ubuntu-core}"
image="${IMAGE:-ubuntu:24.04}"
target_user="${TARGET_USER:-testuser}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$profile" in
    -h|--help)
        usage
        exit 0
        ;;
    syntax|ubuntu-core|ubuntu-agents|ubuntu-skills|ubuntu-workflow-root|ubuntu-workflow-root-dev|ubuntu-workflow-later|ubuntu-workflow-conflict|ubuntu-module-contracts)
        ;;
    *)
        echo "Unknown profile: $profile" >&2
        usage >&2
        exit 2
        ;;
esac

docker run --rm -i --pull=missing \
    --mount "type=bind,src=${repo_root},dst=/repo,readonly" \
    -e DEBIAN_FRONTEND=noninteractive \
    -e TARGET_USER="$target_user" \
    "$image" bash -s -- "$profile" <<'CONTAINER'
set -euo pipefail

profile="$1"
test_password='Ignition-Test-42'
workflow_origin='git@github.com:andrewjamesturner0/ignition.git'

fail() {
    echo "Integration assertion failed: $*" >&2
    exit 1
}

copy_repo() {
    cp -a /repo /tmp/ignition
    chown -R root:root /tmp/ignition
    cd /tmp/ignition
}

commit_worktree_snapshot() {
    git config user.name 'Integration Test'
    git config user.email 'integration@example.test'
    git add -A
    if ! git diff --cached --quiet; then
        git commit -m 'Test current worktree snapshot'
    fi
}

install_bootstrap_packages() {
    if command -v curl >/dev/null && command -v git >/dev/null \
        && command -v sudo >/dev/null && command -v script >/dev/null; then
        return
    fi
    apt-get update
    apt-get install -y ca-certificates curl git sudo util-linux
}

create_target_with_password() {
    local source_dir="$1"
    local transcript="$2"
    local command_text

    command_text="cd '$source_dir' && env TARGET_USER='$TARGET_USER' bash scripts/01-user.sh"
    { sleep 1; printf '%s\n' "$test_password"; sleep 0.2; printf '%s\n' "$test_password"; sleep 1; } \
        | script -qefc "$command_text" "$transcript"
}

prepare_fixture_origin() {
    local source=/tmp/workflow-repo-source

    /usr/bin/git init --bare /tmp/workflow-repo-origin.git
    mkdir -p "$source"
    /usr/bin/git -C "$source" init -b main
    /usr/bin/git -C "$source" config user.name 'Workflow Fixture'
    /usr/bin/git -C "$source" config user.email 'workflow@example.test'
    printf '%s\n' 'workflow fixture repository' > "$source/README.md"
    /usr/bin/git -C "$source" add README.md
    /usr/bin/git -C "$source" commit -m 'Create fixture repository'
    /usr/bin/git -C "$source" remote add origin /tmp/workflow-repo-origin.git
    /usr/bin/git -C "$source" push origin main
    /usr/bin/git -C /tmp/workflow-repo-origin.git symbolic-ref HEAD refs/heads/main
}

prepare_workflow_source() {
    local source=/root/ignition
    local fixtures

    mkdir -p "$source"
    cp -a /repo/. "$source/"
    chown -R root:root "$source"
    rm -rf -- "$source/.git"
    fixtures="$source/tests/fixtures/workflow-modules"
    cp "$fixtures"/0*.sh "$source/scripts/"
    cp "$fixtures/workflow-lib.sh" "$source/scripts/"
    chmod 0755 "$source/scripts/"*.sh
    printf '%s\n' 'git@workflow.test:fixtures/dotfiles.git' > "$source/repos.txt"

    /usr/bin/git -C "$source" init -b main
    /usr/bin/git -C "$source" config user.name 'Integration Test'
    /usr/bin/git -C "$source" config user.email 'integration@example.test'
    /usr/bin/git -C "$source" add -A
    /usr/bin/git -C "$source" commit -m 'Create committed workflow fixture'

    prepare_fixture_origin
    install -m 0755 "$fixtures/fake-ssh" /usr/local/bin/ssh
    install -m 0755 "$fixtures/git-wrapper" /usr/local/bin/git
    install -m 0666 /dev/null /tmp/workflow-git.log
    install -m 0666 /dev/null /tmp/workflow-ssh.log
    install -m 0666 /dev/null /tmp/workflow-modules.log
}

install_sudo_logger() {
    cat > /usr/local/bin/sudo <<'EOF'
#!/bin/sh
printf '%s|%s|%s|%s\n' "$(id -u)" "$(id -un)" "$HOME" "$*" >> /tmp/workflow-sudo.log
exec /usr/bin/sudo "$@"
EOF
    chmod 0755 /usr/local/bin/sudo
    install -m 0666 /dev/null /tmp/workflow-sudo.log
}

run_root_workflow() {
    local checkout="$1"
    local transcript="$2"
    local setup_args="${3:---all}"
    local command_text

    if [[ "$checkout" == "/home/$TARGET_USER/ignition" ]]; then
        command_text="cd /root/ignition && env TARGET_USER='$TARGET_USER' IGNITION_REPO_URL='$workflow_origin' bash setup.sh $setup_args"
    else
        command_text="cd /root/ignition && env TARGET_USER='$TARGET_USER' IGNITION_DIR='$checkout' IGNITION_REPO_URL='$workflow_origin' bash setup.sh $setup_args"
    fi
    { sleep 1; printf '%s\n' "$test_password"; sleep 0.2; printf '%s\n' "$test_password"; sleep 1; } \
        | script -qefc "$command_text" "$transcript"
}

run_later_interactive() {
    local checkout="$1"
    local input="$2"
    local transcript="$3"
    local command_text

    command_text="cd '$checkout' && env TARGET_USER='$TARGET_USER' PATH=/usr/local/bin:/usr/bin:/bin bash setup.sh"
    printf '%b' "$input" \
        | runuser -u "$TARGET_USER" -- env \
            HOME="/home/$TARGET_USER" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
            PATH=/usr/local/bin:/usr/bin:/bin \
            script -qefc "$command_text" "$transcript"
}

run_later_all() {
    local checkout="$1"
    local transcript="$2"
    local command_text

    runuser -u "$TARGET_USER" -- /usr/bin/sudo -k
    command_text="cd '$checkout' && env TARGET_USER='$TARGET_USER' PATH=/usr/local/bin:/usr/bin:/bin bash setup.sh --all"
    { sleep 1; printf '%s\n' "$test_password"; sleep 1; } \
        | runuser -u "$TARGET_USER" -- env \
            HOME="/home/$TARGET_USER" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
            PATH=/usr/local/bin:/usr/bin:/bin \
            script -qefc "$command_text" "$transcript"
}

assert_no_root_owned_home_paths() {
    if find "/home/$TARGET_USER" -xdev ! -user "$TARGET_USER" -print -quit | grep -q .; then
        find "/home/$TARGET_USER" -xdev ! -user "$TARGET_USER" -print >&2
        fail "root-owned paths found in target home"
    fi
}

assert_module_uid() {
    local name="$1"
    local expected_uid="$2"
    grep -q "^${name}|${expected_uid}|" /tmp/workflow-modules.log \
        || fail "module $name did not run as uid $expected_uid"
}

assert_login_commands() {
    local command_name

    for command_name in "$@"; do
        su - "$TARGET_USER" -c "command -v '$command_name' >/dev/null" \
            || fail "$command_name is not available in the target login shell"
    done
}

prepare_module_contracts() {
    local contract_bin=/tmp/module-contract-bin
    local contract_source=/tmp/module-contract-source
    local fixtures=/tmp/ignition/tests/fixtures/module-contracts
    local command_name

    ! id "$TARGET_USER" >/dev/null 2>&1 || fail 'module contract target user already exists'
    useradd -m -d "/home/$TARGET_USER" -s /bin/bash "$TARGET_USER"

    /usr/bin/git init --bare /tmp/module-contract-origin.git
    mkdir -p "$contract_source"
    /usr/bin/git -C "$contract_source" init -b main
    /usr/bin/git -C "$contract_source" config user.name 'Module Contract Fixture'
    /usr/bin/git -C "$contract_source" config user.email 'module-contract@example.test'
    install -m 0755 "$fixtures/dotfiles-install.sh" "$contract_source/install.sh"
    /usr/bin/git -C "$contract_source" add install.sh
    /usr/bin/git -C "$contract_source" commit -m 'Create module contract dotfiles'
    /usr/bin/git -C "$contract_source" remote add origin /tmp/module-contract-origin.git
    /usr/bin/git -C "$contract_source" push origin main
    /usr/bin/git -C /tmp/module-contract-origin.git symbolic-ref HEAD refs/heads/main

    mkdir -p "$contract_bin"
    for command_name in gpg apt wget add-apt-repository Rscript; do
        install -m 0755 "$fixtures/external-command" "$contract_bin/$command_name"
    done
    install -m 0755 "$fixtures/fake-ssh" "$contract_bin/ssh"
    install -m 0666 /dev/null /tmp/module-contract-external.log
    install -m 0666 /dev/null /tmp/module-contract-installer.log
    install -m 0666 /dev/null /tmp/module-contract-ssh.log
    printf '%s\n' 'git@github.com:fixtures/dotfiles.git' > /tmp/ignition/repos.txt
}

run_contract_user_module() {
    local script_name="$1"

    runuser -u "$TARGET_USER" -- env \
        HOME="/home/$TARGET_USER" USER="$TARGET_USER" LOGNAME="$TARGET_USER" \
        TARGET_USER="$TARGET_USER" \
        PATH=/tmp/module-contract-bin:/usr/local/bin:/usr/bin:/bin \
        bash "/tmp/ignition/scripts/$script_name"
}

test_production_module_contracts() {
    local script_name target_uid target_group expected_origin

    install_bootstrap_packages
    copy_repo
    prepare_module_contracts
    target_uid="$(id -u "$TARGET_USER")"
    target_group="$(id -gn "$TARGET_USER")"
    expected_origin='git@github.com:fixtures/dotfiles.git'

    for script_name in 03-ssh.sh 04-repos.sh 05-dotfiles.sh; do
        if env TARGET_USER="$TARGET_USER" \
            PATH=/tmp/module-contract-bin:/usr/local/bin:/usr/bin:/bin \
            bash "scripts/$script_name" >/tmp/module-contract-guard.out 2>&1; then
            fail "$script_name accepted root execution"
        fi
        grep -q "must be run as target user '$TARGET_USER'" /tmp/module-contract-guard.out \
            || fail "$script_name did not report its target-user guard"
    done
    [[ ! -e "/home/$TARGET_USER/.ssh" && ! -e "/home/$TARGET_USER/repos" ]] \
        || fail 'a guarded user module mutated the target home'
    if run_contract_user_module 06-R.sh >/tmp/module-contract-r-guard.out 2>&1; then
        fail '06-R.sh accepted target-user execution'
    fi
    grep -q 'must be run as root' /tmp/module-contract-r-guard.out \
        || fail '06-R.sh did not report its root guard'

    run_contract_user_module 03-ssh.sh
    run_contract_user_module 03-ssh.sh
    [[ "$(stat -c '%U:%G:%a' "/home/$TARGET_USER/.ssh")" == "$TARGET_USER:$target_group:700" ]] \
        || fail 'production SSH directory ownership or mode is wrong'
    [[ "$(stat -c '%U:%G:%a' "/home/$TARGET_USER/.ssh/github.id_rsa")" == "$TARGET_USER:$target_group:600" ]] \
        || fail 'production SSH key ownership or mode is wrong'
    [[ "$(stat -c '%U:%G:%a' "/home/$TARGET_USER/.ssh/config")" == "$TARGET_USER:$target_group:644" ]] \
        || fail 'production SSH config ownership or mode is wrong'
    [[ "$(grep -c "^gpg|${target_uid}|${TARGET_USER}|/home/${TARGET_USER}|" /tmp/module-contract-external.log)" -eq 2 ]] \
        || fail 'production SSH decryption did not rerun as the target user with its home'

    run_contract_user_module 04-repos.sh
    runuser -u "$TARGET_USER" -- /usr/bin/git -C "/home/$TARGET_USER/repos/dotfiles" \
        remote set-url origin git@github.com:wrong/dotfiles.git
    run_contract_user_module 04-repos.sh
    [[ "$(runuser -u "$TARGET_USER" -- /usr/bin/git -C "/home/$TARGET_USER/repos/dotfiles" remote get-url origin)" == "$expected_origin" ]] \
        || fail 'production repos module did not repair origin'
    grep -Eq "^${target_uid}\|${TARGET_USER}\|/home/${TARGET_USER}\|loaded:" /tmp/module-contract-ssh.log \
        || fail 'production repos Git did not use the target UID, home, and SSH config'

    run_contract_user_module 05-dotfiles.sh
    run_contract_user_module 05-dotfiles.sh
    [[ "$(grep -c "^${target_uid}|${TARGET_USER}|/home/${TARGET_USER}$" /tmp/module-contract-installer.log)" -eq 2 ]] \
        || fail 'production dotfiles installer did not rerun with the target UID and home'
    [[ "$(grep -cxF 'export MODULE_CONTRACT_DOTFILES=ready' "/home/$TARGET_USER/.profile")" -eq 1 ]] \
        || fail 'production dotfiles rerun duplicated profile state'
    assert_no_root_owned_home_paths

    env TARGET_USER="$TARGET_USER" HOME=/root \
        PATH=/tmp/module-contract-bin:/usr/local/bin:/usr/bin:/bin bash scripts/06-R.sh
    env TARGET_USER="$TARGET_USER" HOME=/root \
        PATH=/tmp/module-contract-bin:/usr/local/bin:/usr/bin:/bin bash scripts/06-R.sh
    [[ "$(grep -c '^Rscript|0|root|/root|' /tmp/module-contract-external.log)" -eq 2 ]] \
        || fail 'production R installer did not rerun as root with root home'
}

assert_root_workflow() {
    local checkout="$1"
    local transcript="$2"
    local target_uid target_group

    target_uid="$(id -u "$TARGET_USER")"
    target_group="$(id -gn "$TARGET_USER")"
    [[ "$(getent shadow "$TARGET_USER" | cut -d: -f2)" != '!'* ]] \
        || fail "target password is locked"
    id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx sudo \
        || fail "target user is not in sudo group"
    grep -q 'New password:' "$transcript" \
        || fail "real passwd prompt was not observed"
    grep -q 'Module user effective user=root uid=0' "$transcript" \
        || fail "user module root identity was not logged"

    [[ -d "$checkout/.git" ]] || fail "target checkout is not a Git worktree"
    [[ "$(runuser -u "$TARGET_USER" -- /usr/bin/git -C "$checkout" remote get-url origin)" == "$workflow_origin" ]] \
        || fail "target checkout origin is wrong"
    [[ "$(runuser -u "$TARGET_USER" -- /usr/bin/git -C "$checkout" symbolic-ref --short HEAD)" == main ]] \
        || fail "target checkout HEAD is not main"
    [[ "$(stat -c '%U:%G' "$checkout/.git/index")" == "$TARGET_USER:$target_group" ]] \
        || fail "target checkout index ownership is wrong"
    grep -Eq "^${target_uid}\|${TARGET_USER}\|/home/${TARGET_USER}\|clone --branch main -- /tmp/ignition-transfer[.]" /tmp/workflow-git.log \
        || fail "target checkout clone did not run as target uid"
    grep -Eq "^${target_uid}\|${TARGET_USER}\|/home/${TARGET_USER}\|loaded:" /tmp/workflow-ssh.log \
        || fail "repository Git did not use target uid and SSH config"

    assert_module_uid packages 0
    assert_module_uid ssh "$target_uid"
    assert_module_uid repos "$target_uid"
    assert_module_uid dotfiles "$target_uid"
    assert_module_uid R 0
    assert_module_uid 'nodejs prerequisites' 0
    assert_module_uid nodejs "$target_uid"
    assert_module_uid agents "$target_uid"
    assert_module_uid skills "$target_uid"

    [[ ! -e /root/.nvm && ! -e /root/.ssh/github.id_rsa && ! -e /root/agent-skills ]] \
        || fail "user-scoped fixture state was written under /root"
    ! compgen -G '/tmp/ignition-transfer.*' >/dev/null \
        || fail "Git bundle transfer directory was not removed"
    assert_no_root_owned_home_paths

    install_sudo_logger
    if runuser -u "$TARGET_USER" -- env PATH=/usr/local/bin:/usr/bin:/bin sudo -n true; then
        fail "sudo accepted a command without the target password"
    fi
    { sleep 1; printf '%s\n' "$test_password"; sleep 1; } \
        | runuser -u "$TARGET_USER" -- env HOME="/home/$TARGET_USER" PATH=/usr/local/bin:/usr/bin:/bin \
            script -qefc 'sudo -k; sudo true' /tmp/password-sudo.typescript
    grep -q "|${TARGET_USER}|/home/${TARGET_USER}|true" /tmp/workflow-sudo.log \
        || fail "password-protected sudo was not exercised through the logger"
    if grep -Rqs 'NOPASSWD' /etc/sudoers /etc/sudoers.d; then
        fail "a NOPASSWD sudo rule exists"
    fi
}

bootstrap_fixture_workflow() {
    local checkout="$1"
    install_bootstrap_packages
    prepare_workflow_source
    ! id "$TARGET_USER" >/dev/null 2>&1 || fail "target user existed before root-first setup"
    run_root_workflow "$checkout" /tmp/root-first.typescript
    assert_root_workflow "$checkout" /tmp/root-first.typescript
}

test_private_skills_clone() {
    local target_home="/home/$TARGET_USER"
    local skills_dir="$target_home/agent-skills"
    local expected_url="git@github.com:andrewjamesturner0/agent-skills.git"

    create_target_with_password /tmp/ignition /tmp/skills-user.typescript
    install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$target_home/.ssh"
    install -m 600 -o "$TARGET_USER" -g "$TARGET_USER" /dev/null "$target_home/.ssh/github.id_rsa"
    install -m 644 -o "$TARGET_USER" -g "$TARGET_USER" ssh/config "$target_home/.ssh/config"

    git init --bare /tmp/agent-skills-origin.git
    git init /tmp/agent-skills-source
    git -C /tmp/agent-skills-source config user.name 'Integration Test'
    git -C /tmp/agent-skills-source config user.email 'integration@example.test'
    mkdir -p /tmp/agent-skills-source/skills/example /tmp/agent-skills-source/conventions
    printf '%s\n' '# Example skill' > /tmp/agent-skills-source/skills/example/SKILL.md
    printf '%s\n' '# Test conventions' > /tmp/agent-skills-source/conventions/global.md
    git -C /tmp/agent-skills-source add .
    git -C /tmp/agent-skills-source commit -m 'Add test skills'
    git -C /tmp/agent-skills-source remote add origin /tmp/agent-skills-origin.git
    git -C /tmp/agent-skills-source push origin HEAD:main
    git -C /tmp/agent-skills-origin.git symbolic-ref HEAD refs/heads/main
    chown -R "$TARGET_USER:$TARGET_USER" /tmp/agent-skills-origin.git

    install -m 755 tests/fixtures/fake-ssh /usr/local/bin/ssh
    install -m 666 /dev/null /tmp/ssh-invocations

    runuser -u "$TARGET_USER" -- env TARGET_USER="$TARGET_USER" HOME="$target_home" \
        PATH=/usr/local/bin:/usr/bin:/bin bash scripts/09-agent-skills.sh

    test "$(runuser -u "$TARGET_USER" -- git -C "$skills_dir" remote get-url origin)" = "$expected_url"
    grep -q -- "-F $target_home/.ssh/config" /tmp/ssh-invocations
    grep -q -- "-i $target_home/.ssh/github.id_rsa" /tmp/ssh-invocations
    grep -q -- '-o IdentitiesOnly=yes' /tmp/ssh-invocations
    grep -q -- '-o BatchMode=yes' /tmp/ssh-invocations
    grep -q -- '-o StrictHostKeyChecking=accept-new' /tmp/ssh-invocations

    runuser -u "$TARGET_USER" -- git -C "$skills_dir" remote set-url origin \
        https://github.com/andrewjamesturner0/agent-skills
    install -m 666 /dev/null /tmp/ssh-invocations
    runuser -u "$TARGET_USER" -- env TARGET_USER="$TARGET_USER" HOME="$target_home" \
        PATH=/usr/local/bin:/usr/bin:/bin bash scripts/09-agent-skills.sh

    test "$(runuser -u "$TARGET_USER" -- git -C "$skills_dir" remote get-url origin)" = "$expected_url"
    test -s /tmp/ssh-invocations

    if runuser -u "$TARGET_USER" -- env TARGET_USER="$TARGET_USER" HOME="$target_home" \
        PATH=/usr/local/bin:/usr/bin:/bin \
        AGENT_SKILLS_REPO_URL=https://github.com/andrewjamesturner0/agent-skills \
        bash scripts/09-agent-skills.sh; then
        fail 'HTTPS agent skills URL was accepted'
    fi
}

case "$profile" in
    syntax)
        copy_repo
        bash -n setup.sh lib/common.sh lib/modules.sh scripts/*.sh ssh/*.sh \
            tests/docker-integration.sh tests/selection.sh \
            tests/fixtures/module-contracts/* \
            tests/fixtures/workflow-modules/*.sh \
            tests/fixtures/workflow-modules/fake-ssh \
            tests/fixtures/workflow-modules/git-wrapper
        ;;
    ubuntu-core)
        install_bootstrap_packages
        copy_repo
        commit_worktree_snapshot
        command_text="cd /tmp/ignition && env TARGET_USER='$TARGET_USER' bash setup.sh --skip=ssh,repos,dotfiles,R,agents,skills"
        { sleep 1; printf '%s\n' "$test_password"; sleep 0.2; printf '%s\n' "$test_password"; sleep 1; } \
            | script -qefc "$command_text" /tmp/core.typescript
        assert_login_commands node npm
        ;;
    ubuntu-agents)
        install_bootstrap_packages
        copy_repo
        commit_worktree_snapshot
        command_text="cd /tmp/ignition && env TARGET_USER='$TARGET_USER' bash setup.sh --skip=ssh,repos,dotfiles,R,skills"
        { sleep 1; printf '%s\n' "$test_password"; sleep 0.2; printf '%s\n' "$test_password"; sleep 1; } \
            | script -qefc "$command_text" /tmp/agents.typescript
        ;;
    ubuntu-skills)
        install_bootstrap_packages
        copy_repo
        test_private_skills_clone
        ;;
    ubuntu-workflow-root)
        bootstrap_fixture_workflow "/home/$TARGET_USER/ignition"
        script -qefc \
            "cd /root/ignition && env TARGET_USER='$TARGET_USER' IGNITION_REPO_URL='$workflow_origin' bash setup.sh --all" \
            /tmp/root-resume.typescript </dev/null
        grep -q "Reusing target-user checkout at /home/$TARGET_USER/ignition" /tmp/root-resume.typescript \
            || fail 'root-first resume did not log target checkout reuse'
        assert_no_root_owned_home_paths
        ;;
    ubuntu-workflow-root-dev)
        bootstrap_fixture_workflow "/home/$TARGET_USER/Dev/ignition"
        ;;
    ubuntu-workflow-later)
        checkout="/home/$TARGET_USER/ignition"
        bootstrap_fixture_workflow "$checkout"
        mv /root/ignition /root/ignition.bootstrap
        assert_login_commands node npm claude codex pi

        install -m 0666 /dev/null /tmp/workflow-sudo.log
        install -m 0666 /dev/null /tmp/workflow-modules.log
        run_later_interactive "$checkout" 'n\n8\n2\n\n' /tmp/later-user.typescript
        grep -q 'Added nodejs because agents requires it' /tmp/later-user.typescript
        grep -q 'Added packages because nodejs requires it' /tmp/later-user.typescript
        grep -q 'Cannot deselect packages because nodejs requires it' /tmp/later-user.typescript
        grep -q 'Prerequisite user is already satisfied' /tmp/later-user.typescript
        grep -q 'Prerequisite packages is already satisfied' /tmp/later-user.typescript
        grep -q 'Prerequisite nodejs is already satisfied' /tmp/later-user.typescript
        [[ ! -s /tmp/workflow-sudo.log ]] || fail 'user-only selection invoked sudo'
        assert_module_uid agents "$(id -u "$TARGET_USER")"

        install -m 0666 /dev/null /tmp/workflow-sudo.log
        install -m 0666 /dev/null /tmp/workflow-modules.log
        runuser -u "$TARGET_USER" -- /usr/bin/sudo -k
        run_later_interactive "$checkout" "n\n6\n\n${test_password}\n" /tmp/later-system.typescript
        grep -q '|-- env TARGET_USER=' /tmp/workflow-sudo.log \
            || fail 'system selection did not invoke logged sudo'
        assert_module_uid R 0

        run_later_all "$checkout" /tmp/rerun-one.typescript
        run_later_all "$checkout" /tmp/rerun-two.typescript
        [[ "$(grep -cxF 'export WORKFLOW_FIXTURE=ready' "/home/$TARGET_USER/.profile")" -eq 1 ]] \
            || fail 'rerun duplicated fixture profile configuration'
        [[ "$(find "/home/$TARGET_USER/repos" -mindepth 1 -maxdepth 1 -type d -name dotfiles | wc -l)" -eq 1 ]] \
            || fail 'rerun duplicated repository checkout'
        assert_no_root_owned_home_paths
        ;;
    ubuntu-workflow-conflict)
        mkdir -p /root/ignition
        cp -a /repo/. /root/ignition/
        if env TARGET_USER="$TARGET_USER" bash /root/ignition/setup.sh --skip=packages \
            >/tmp/conflict.out 2>&1; then
            fail 'explicit dependency conflict succeeded'
        fi
        grep -q 'Cannot select ssh while skipping required component packages' /tmp/conflict.out \
            || { cat /tmp/conflict.out >&2; fail 'dependency conflict did not name ssh and packages'; }
        if grep -q -- '------ Running:' /tmp/conflict.out; then
            cat /tmp/conflict.out >&2
            fail 'a module started before dependency failure'
        fi
        ! id "$TARGET_USER" >/dev/null 2>&1 || fail 'dependency failure created the target user'
        [[ ! -e /var/lib/ignition && ! -e "/home/$TARGET_USER" ]] \
            || fail 'dependency failure created module state'
        ;;
    ubuntu-module-contracts)
        test_production_module_contracts
        ;;
esac
CONTAINER
