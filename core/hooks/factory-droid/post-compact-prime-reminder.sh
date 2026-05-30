#!/usr/bin/env bash
# SessionStart hook: reload bd context after a compaction.
#
# Locates the directory that owns `.beads/` (walking up from the current
# directory, or honouring $BEADS_DIR), runs `bd prime` there, and injects the
# output as additionalContext so the restored session reloads workflow context,
# durable memories, and ready tasks. If bd prime fails or is empty, injects a
# generic recovery reminder instead. No organisation-specific path is assumed.

set -u

command -v bd >/dev/null 2>&1 || exit 0

BD_CWD=$(python3 - <<'PY'
import os
from pathlib import Path

candidates = []
env_dir = os.environ.get("BEADS_DIR")
if env_dir:
    candidates.append(Path(os.path.expanduser(env_dir)))
candidates.append(Path.cwd())

seen = set()
for candidate in candidates:
    try:
        current = candidate.resolve()
    except Exception:
        continue
    for path in [current, *current.parents]:
        if path in seen:
            continue
        seen.add(path)
        if (path / ".beads").is_dir():
            print(path)
            raise SystemExit
PY
)

if [ -n "$BD_CWD" ]; then
  PRIME_OUTPUT=$(cd "$BD_CWD" && bd prime 2>/dev/null)
else
  PRIME_OUTPUT=$(bd prime 2>/dev/null)
fi
PRIME_EXIT=$?

if [ "$PRIME_EXIT" -eq 0 ] && [ -n "$PRIME_OUTPUT" ]; then
  ESCAPED=$(printf '%s' "$PRIME_OUTPUT" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read())[1:-1])')
  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "This session was restored after context compression. bd prime output is injected below (ran from: ${BD_CWD:-current directory}). Verify the memories reflect the previous session's work — if they look stale or are missing recent work, update them with bd remember.\n\n--- bd prime output ---\n${ESCAPED}\n--- end bd prime output ---"
  }
}
ENDJSON
else
  cat <<'ENDJSON'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "This session was restored after context compression. bd prime failed or returned empty output. Run `bd where`, then run `bd prime` from the repo root that owns `.beads/` (or set BEADS_DIR). Then verify that bd memories reflect the previous session's work — if they look stale, update them with bd remember."
  }
}
ENDJSON
fi

exit 0
