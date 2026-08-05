#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/workflow-lib.sh"

workflow_require_target
workflow_record
skills_dir="${AGENT_SKILLS_DIR:-$TARGET_HOME/agent-skills}"
claude_home="${CLAUDE_HOME:-$TARGET_HOME/.claude}"
codex_home="${CODEX_HOME:-$TARGET_HOME/.codex}"
pi_home="${PI_AGENT_HOME:-$TARGET_HOME/.pi/agent}"
origin="${AGENT_SKILLS_REPO_URL:-git@github.com:andrewjamesturner0/agent-skills.git}"

mkdir -p "$skills_dir/skills/example" "$skills_dir/conventions"
printf '%s\n' '# Fixture skill' > "$skills_dir/skills/example/SKILL.md"
printf '%s\n' '# Fixture conventions' > "$skills_dir/conventions/global.md"
if [[ ! -d "$skills_dir/.git" ]]; then
    git -C "$skills_dir" init
    git -C "$skills_dir" config user.name 'Workflow Fixture'
    git -C "$skills_dir" config user.email 'workflow@example.test'
    git -C "$skills_dir" add .
    git -C "$skills_dir" commit -m 'Create workflow fixture skills'
fi
if git -C "$skills_dir" remote get-url origin >/dev/null 2>&1; then
    git -C "$skills_dir" remote set-url origin "$origin"
else
    git -C "$skills_dir" remote add origin "$origin"
fi

mkdir -p "$claude_home" "$codex_home/skills" "$pi_home"
ln -sfn "$skills_dir/skills" "$claude_home/skills"
ln -sfn "$skills_dir/conventions/global.md" "$claude_home/CLAUDE.md"
ln -sfn "$skills_dir/skills" "$pi_home/skills"
ln -sfn "$skills_dir/conventions/global.md" "$pi_home/APPEND_SYSTEM.md"
ln -sfn "$skills_dir/skills/example" "$codex_home/skills/example"
ln -sfn "$skills_dir/conventions/global.md" "$codex_home/AGENTS.md"
