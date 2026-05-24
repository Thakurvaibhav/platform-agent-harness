#!/usr/bin/env bash
# Minimal statusline showing repo, branch, Graphify availability, and bd state.
#
# Pipe the runtime's session-state JSON into statusline-context.py for the
# context-window utilization indicator.

set -euo pipefail

cwd="${PWD}"
branch="$(git --no-optional-locks branch --show-current 2>/dev/null || true)"

graph=""
[ -f "graphify-out/graph.json" ] && graph=" graphify"

bd_state=""
if command -v bd >/dev/null 2>&1 && [ -d ".beads" ]; then
  bd_state=" bd"
fi

printf "[%s%s%s] %s" "$(basename "$cwd")" "${branch:+:$branch}" "$graph$bd_state" "$ "
