#!/usr/bin/env bash
# Generic SessionStart / pre-task hook.
#
# Verifies required tools are installed, notes Graphify availability,
# and runs `bd prime` if the current directory is a bd-initialized repo.
#
# Portable shell — adapt to your runtime's session-start hook mechanism.

set -u

missing=()
for t in git bd graphify rtk jq yq; do
  command -v "$t" >/dev/null 2>&1 || missing+=("$t")
done

if [ ${#missing[@]} -gt 0 ]; then
  printf "[harness] missing required tools: %s\n" "${missing[*]}" >&2
fi

if [ -f "graphify-out/graph.json" ]; then
  printf "[harness] graphify-out/graph.json detected — prefer graphify queries over linear file reads.\n"
fi

if [ -d ".beads" ] && command -v bd >/dev/null 2>&1; then
  bd prime 2>/dev/null || true
fi

exit 0
