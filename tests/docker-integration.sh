#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tests/docker-integration.sh [profile]

Profiles:
  syntax          Run shell syntax checks in a disposable Ubuntu container.
  ubuntu-core     Run user, packages, and nodejs modules in Ubuntu. Default.
  ubuntu-agents   Run user, packages, nodejs, and agents modules in Ubuntu. Uses live upstream installers.
  ubuntu-skills   Test private skills cloning through the configured SSH key.

Environment:
  IMAGE           Docker image to use. Default: ubuntu:24.04
  TARGET_USER     User created inside the container. Default: testuser

Notes:
  The repo is mounted read-only and copied to /tmp/ignition inside the container.
  Docker profiles skip private agent skills because no GitHub SSH key is installed.
  The default profile also skips SSH, repos, dotfiles, R, and agents.
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
    syntax|ubuntu-core|ubuntu-agents|ubuntu-skills)
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

copy_repo() {
    cp -a /repo /tmp/ignition
    cd /tmp/ignition
}

install_bootstrap_packages() {
    apt-get update
    apt-get install -y ca-certificates curl
}

test_private_skills_clone() {
    local target_home="/home/$TARGET_USER"
    local skills_dir="$target_home/agent-skills"
    local expected_url="git@github.com:andrewjamesturner0/agent-skills.git"

    apt-get update
    apt-get install -y git

    bash scripts/01-user.sh
    install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$target_home/.ssh"
    install -m 600 -o "$TARGET_USER" -g "$TARGET_USER" /dev/null "$target_home/.ssh/github.id_rsa"
    install -m 644 -o "$TARGET_USER" -g "$TARGET_USER" ssh/config "$target_home/.ssh/config"

    git init --bare /tmp/agent-skills-origin.git
    git init /tmp/agent-skills-source
    git -C /tmp/agent-skills-source config user.name "Integration Test"
    git -C /tmp/agent-skills-source config user.email "integration@example.test"
    mkdir -p /tmp/agent-skills-source/skills/example /tmp/agent-skills-source/conventions
    printf '%s\n' '# Example skill' > /tmp/agent-skills-source/skills/example/SKILL.md
    printf '%s\n' '# Test conventions' > /tmp/agent-skills-source/conventions/global.md
    git -C /tmp/agent-skills-source add .
    git -C /tmp/agent-skills-source commit -m "Add test skills"
    git -C /tmp/agent-skills-source remote add origin /tmp/agent-skills-origin.git
    git -C /tmp/agent-skills-source push origin HEAD:main
    git -C /tmp/agent-skills-origin.git symbolic-ref HEAD refs/heads/main
    chown -R "$TARGET_USER:$TARGET_USER" /tmp/agent-skills-origin.git

    install -m 755 tests/fixtures/fake-ssh /usr/local/bin/ssh
    install -m 666 /dev/null /tmp/ssh-invocations

    bash scripts/09-agent-skills.sh

    test "$(su - "$TARGET_USER" -c "git -C '$skills_dir' remote get-url origin")" = "$expected_url"
    grep -q -- "-F $target_home/.ssh/config" /tmp/ssh-invocations
    grep -q -- "-i $target_home/.ssh/github.id_rsa" /tmp/ssh-invocations
    grep -q -- "-o IdentitiesOnly=yes" /tmp/ssh-invocations
    grep -q -- "-o BatchMode=yes" /tmp/ssh-invocations
    grep -q -- "-o StrictHostKeyChecking=accept-new" /tmp/ssh-invocations

    su - "$TARGET_USER" -c \
        "git -C '$skills_dir' remote set-url origin https://github.com/andrewjamesturner0/agent-skills"
    install -m 666 /dev/null /tmp/ssh-invocations
    bash scripts/09-agent-skills.sh

    test "$(su - "$TARGET_USER" -c "git -C '$skills_dir' remote get-url origin")" = "$expected_url"
    test -s /tmp/ssh-invocations

    if AGENT_SKILLS_REPO_URL=https://github.com/andrewjamesturner0/agent-skills \
        bash scripts/09-agent-skills.sh; then
        echo "HTTPS agent skills URL was accepted" >&2
        exit 1
    fi
}

case "$profile" in
    syntax)
        copy_repo
        bash -n setup.sh lib/common.sh scripts/*.sh ssh/*.sh
        ;;
    ubuntu-core)
        install_bootstrap_packages
        copy_repo
        bash setup.sh --skip=ssh,repos,dotfiles,R,agents,skills
        ;;
    ubuntu-agents)
        install_bootstrap_packages
        copy_repo
        bash setup.sh --skip=ssh,repos,dotfiles,R,skills
        ;;
    ubuntu-skills)
        copy_repo
        test_private_skills_clone
        ;;
esac
CONTAINER
