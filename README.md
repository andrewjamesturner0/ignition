# Ignition

Ignition sets up a Debian, Ubuntu, or Arch-based development machine. It supports a first run as root on a new system and later selective runs as the target user. The default target user is `ajt`.

System changes run as root. User tools, repositories, SSH files, and configuration are created directly as the target user, so files beneath the target home do not end up owned by root.

## Prerequisites

For the first run you need:

- A supported Debian, Ubuntu, or Arch-based system.
- An interactive root shell.
- Bash and Git, plus network access for package and tool downloads.
- Access to the repositories listed in `repos.txt`.
- The passphrase for `ssh/github.id_rsa.gpg` if you select the `ssh` component.

Docker is needed only to run the integration tests.

## First run on a new system

Clone a disposable bootstrap copy under `/root`, then run it as root:

```sh
git clone https://github.com/andrewjamesturner0/ignition.git /root/ignition
cd /root/ignition
./setup.sh
```

The interactive selector starts with every default component selected except `R`. Use `./setup.sh --all` to select every component, including `R`.

If `ajt` does not exist, Ignition creates the account and runs the system password prompt. The password is required for later `sudo` use. Ignition adds the new account to the normal administrative group, but does not install a `NOPASSWD` rule. An existing account and its password are left unchanged.

The first run completes from the bootstrap copy and creates a lasting checkout owned by `ajt` at:

```text
/home/ajt/ignition
```

To put it under `Dev` instead, set `IGNITION_DIR` on the first run:

```sh
cd /root/ignition
IGNITION_DIR=/home/ajt/Dev/ignition ./setup.sh
```

The lasting checkout keeps the SSH origin `git@github.com:andrewjamesturner0/ignition.git`. The bootstrap copy under `/root` is not needed for later runs.

If a selected module fails after the lasting checkout is created, rerun the same command from the unchanged bootstrap copy. Ignition reuses the checkout only when its owner, branch, commit, and SSH origin match the bootstrap. It rejects an unrelated destination without changing it.

## Later runs

Log in as `ajt` and run Ignition from its lasting checkout without a leading `sudo`:

```sh
cd /home/ajt/ignition
./setup.sh
```

For the `Dev` location, use `cd /home/ajt/Dev/ignition` instead. Ignition runs user-scoped work directly and requests `sudo` only when a selected system component needs it.

The command-line forms are:

```text
./setup.sh
./setup.sh --all
./setup.sh --skip=module1,module2
./setup.sh --help
```

Use only one of `--all` or `--skip`. An explicit skip that conflicts with a selected component's dependency fails before any module runs.

## Components and dependencies

| Component | Default | What it does |
| --- | --- | --- |
| `user` | on | Creates the target user with password-protected administrative access. |
| `packages` | on | Installs core development packages. |
| `ssh` | on | Decrypts and installs the GitHub SSH key and config. |
| `repos` | on | Clones or updates repositories from `repos.txt`. |
| `dotfiles` | on | Runs the installer from the cloned dotfiles repository. |
| `R` | off | Installs R, tidyverse, rmarkdown, and knitr. |
| `nodejs` | on | Installs system prerequisites, then nvm, Node.js, and npm for the target user. |
| `agents` | on | Installs Claude Code, Codex CLI, and pi. |
| `skills` | on | Clones and links the private coding-agent skills repository. |

The selector adds required components automatically and explains each addition. The dependency graph is:

- `ssh` requires `user` and `packages`.
- `repos` requires `user` and `packages`.
- `dotfiles` requires `repos`.
- `nodejs` requires `user` and `packages`.
- `agents` requires `nodejs`.
- `skills` requires `ssh`.

Ignition does not rerun automatically added prerequisites when they are already satisfied. This avoids an unnecessary `sudo` prompt during a later user-only run.

## Useful overrides

- `TARGET_USER` changes the target account from the default `ajt`. A new account uses `/home/$TARGET_USER`.
- `IGNITION_DIR` selects `/home/$TARGET_USER/ignition` or `/home/$TARGET_USER/Dev/ignition` during root-first setup.
- `IGNITION_REPO_URL` changes the lasting checkout's origin and must be an SSH URL.
- `NODE_MAJOR` changes the Node.js major version from the default `24`.
- `AGENT_SKILLS_REPO_URL` changes the private skills repository and must be an SSH URL.

## SSH prompt and reruns

The `ssh` component decrypts `ssh/github.id_rsa.gpg` into the target user's `~/.ssh` directory. GPG or its pinentry program will request the key passphrase. The installed private key has mode `600`, and the SSH config has mode `644`.

Components are safe to rerun after success or a partial failure. Reruns update existing state without duplicating users, repositories, links, shell configuration lines, or tool installations.

## Verification

At the end of a run, Ignition checks the target account, checkout ownership and origin, selected tools, SSH permissions, and agent-skill links. It prints `[OK]` or `[FAIL]` for each check and exits non-zero if any check fails.

The Docker integration profiles are:

```sh
tests/docker-integration.sh syntax
tests/docker-integration.sh ubuntu-workflow-root
tests/docker-integration.sh ubuntu-workflow-root-dev
tests/docker-integration.sh ubuntu-workflow-later
tests/docker-integration.sh ubuntu-workflow-conflict
tests/docker-integration.sh ubuntu-module-contracts
tests/docker-integration.sh ubuntu-skills
tests/docker-integration.sh ubuntu-core
tests/docker-integration.sh ubuntu-agents
```

- `syntax` checks shell syntax in Ubuntu.
- `ubuntu-workflow-root` tests the root-first flow and default checkout using fixtures.
- `ubuntu-workflow-root-dev` tests the `IGNITION_DIR` override using fixtures.
- `ubuntu-workflow-later` tests later user and system selections, privilege boundaries, and reruns using fixtures.
- `ubuntu-workflow-conflict` tests dependency failure before mutation.
- `ubuntu-module-contracts` tests the production SSH, repository, dotfiles, and R modules with offline external-command fixtures.
- `ubuntu-skills` tests private skills cloning through the configured SSH transport and local fixtures.
- `ubuntu-core` runs core components with live upstream installers. It is also the default profile when no profile is given.
- `ubuntu-agents` runs the coding-agent installers live and needs external network services to be available.

Use `IMAGE` to change the Docker image and `TARGET_USER` to change the disposable test account. Both `ubuntu-core` and `ubuntu-agents` depend on live upstream services; the workflow profiles do not.
