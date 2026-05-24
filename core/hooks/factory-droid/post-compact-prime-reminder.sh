#!/usr/bin/env bash
# SessionStart hook: reload bd context after a compaction.
#
# Runs `bd prime` if the current directory is a bd-initialized repo so the
# next session starts with workflow context, durable memories, and ready
# tasks already loaded.

set -u

if [ -d ".beads" ] && command -v bd >/dev/null 2>&1; then
  bd prime 2>/dev/null || true
fi

exit 0
