#!/usr/bin/env bash
# SessionStart hook: reload bd context after a compaction.
#
# Locates the directory that owns `.beads/` (walking up from the current
# directory, or honouring $BEADS_DIR), runs `bd prime` there, and injects the
# output as additionalContext so the restored session reloads workflow context,
# durable memories, and ready tasks. If bd prime fails or is empty, injects a
# generic recovery reminder instead. No organisation-specific path is assumed.
#
# Also reads back the session checkpoint written by pre-compact-bd-sync.py. The two
# halves ship together: a checkpoint nobody reads is a write-only loop.

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

# pre-compact-bd-sync.py writes the session checkpoint here. Recovery has to read it
# back, or the checkpoint is written and never seen — keep this path in step with that
# hook's CHECKPOINT_DIR.
CKPT_DIR="${PRECOMPACT_DIR:-${HARNESS_HOME:-$HOME/.agent-knowledge}/pre-compact}"
CKPT_FILE=""
CKPT=""
if [ -d "$CKPT_DIR" ]; then
  CKPT_FILE=$(ls -t "$CKPT_DIR"/*.md 2>/dev/null | head -1)
  if [ -n "$CKPT_FILE" ]; then
    CKPT=$(cat "$CKPT_FILE" 2>/dev/null)
  fi
fi

if [ "$PRIME_EXIT" -eq 0 ] && [ -n "$PRIME_OUTPUT" ]; then
  ESCAPED=$(printf '%s' "$PRIME_OUTPUT" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read())[1:-1])')
  CKPT_BLOCK=""
  if [ -n "$CKPT" ]; then
    ESCAPED_CKPT=$(printf '%s' "$CKPT" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read())[1:-1])')
    CKPT_BLOCK="\\n\\n--- pre-compact checkpoint ($CKPT_FILE) ---\\n${ESCAPED_CKPT}\\n--- end checkpoint ---"
  fi
  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "This session was restored after context compression. bd prime output is injected below (ran from: ${BD_CWD:-current directory}). Verify the memories reflect the previous session's work — if they look stale or are missing recent work, update them with bd remember.\n\n--- bd prime output ---\n${ESCAPED}\n--- end bd prime output ---${CKPT_BLOCK}"
  }
}
ENDJSON
else
  # The checkpoint matters MORE here, not less: bd prime gave us nothing, so it is the
  # only record of the previous session. Prose uses single quotes, never backticks —
  # this heredoc interpolates, and a backtick in it would run as a command.
  CKPT_BLOCK=""
  if [ -n "$CKPT" ]; then
    ESCAPED_CKPT=$(printf '%s' "$CKPT" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read())[1:-1])')
    CKPT_BLOCK="\\n\\n--- pre-compact checkpoint ($CKPT_FILE) ---\\n${ESCAPED_CKPT}\\n--- end checkpoint ---"
  fi
  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "This session was restored after context compression. bd prime failed or returned empty output. Run 'bd where', then run 'bd prime' from the repo root that owns '.beads/' (or set BEADS_DIR). Then verify that bd memories reflect the previous session's work — if they look stale, update them with bd remember.${CKPT_BLOCK}"
  }
}
ENDJSON
fi

exit 0
