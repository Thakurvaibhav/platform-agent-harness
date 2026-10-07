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

# pre-compact-bd-sync.py keys its checkpoint by session id; read back THIS session's
# file only. Newest-wins would inject a sibling session's state, or a months-old one.
CKPT_DIR="${PRECOMPACT_DIR:-${HARNESS_HOME:-$HOME/.agent-knowledge}/pre-compact}"
CKPT_FILE=""
CKPT=""
SID=""
if [ ! -t 0 ]; then
  SID=$(python3 -c 'import sys, json
try:
    print(str((json.load(sys.stdin) or {}).get("session_id") or "")[:64])
except Exception:
    pass' 2>/dev/null | tr -cd 'A-Za-z0-9_-')
fi
# Mirrors the writer's own fallback when the runtime supplies no session id.
[ -n "$SID" ] || SID="unknown"
if [ -f "$CKPT_DIR/$SID.md" ]; then
  CKPT_FILE="$CKPT_DIR/$SID.md"
  CKPT=$(cat "$CKPT_FILE" 2>/dev/null)
  rm -f "$CKPT_FILE"
fi
# Orphans: a session that compacted and never restarted leaves its file behind.
find "$CKPT_DIR" -name '*.md' -mtime +7 -delete 2>/dev/null

# Built once: the two output branches differ only in their prose.
CKPT_BLOCK=""
if [ -n "$CKPT" ]; then
  ESCAPE='import sys, json; print(json.dumps(sys.stdin.read())[1:-1])'
  ESCAPED_CKPT=$(printf '%s' "$CKPT" | python3 -c "$ESCAPE")
  ESCAPED_CKPT_FILE=$(printf '%s' "$CKPT_FILE" | python3 -c "$ESCAPE")
  CKPT_BLOCK="\\n\\n--- pre-compact checkpoint ($ESCAPED_CKPT_FILE) ---\\n${ESCAPED_CKPT}\\n--- end checkpoint ---"
fi

if [ "$PRIME_EXIT" -eq 0 ] && [ -n "$PRIME_OUTPUT" ]; then
  ESCAPED=$(printf '%s' "$PRIME_OUTPUT" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read())[1:-1])')
  cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "This session was restored after context compression. bd prime output is injected below (ran from: ${BD_CWD:-current directory}). Verify the memories reflect the previous session's work — if they look stale or are missing recent work, update them with bd remember.\n\n--- bd prime output ---\n${ESCAPED}\n--- end bd prime output ---${CKPT_BLOCK}"
  }
}
ENDJSON
else
  # bd prime gave us nothing, so the checkpoint is the only record left. Prose below uses
  # single quotes: this heredoc interpolates, and a backtick in it would run as a command.
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
