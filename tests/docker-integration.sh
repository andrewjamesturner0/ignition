#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: tests/docker-integration.sh [profile]

Profiles:
  syntax          Run shell syntax checks in a disposable Ubuntu container.
  ubuntu-core     Run user, packages, and nodejs modules in Ubuntu. Default.
  ubuntu-agents   Run user, packages, nodejs, and agents modules in Ubuntu. Uses live upstream installers.

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
    syntax|ubuntu-core|ubuntu-agents)
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
esac
CONTAINER
