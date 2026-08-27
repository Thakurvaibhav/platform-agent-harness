#!/usr/bin/env bash
# auto-consolidate.sh — scheduled, threshold-guarded knowledge consolidation.
#
# Run by a scheduler (launchd, cron, systemd timer). Executes the consolidation
# workflow headlessly ONLY when the hive has grown enough to be worth it.
# Conservative + recoverable: the workflow never prunes learnings by usage, and
# every bd deletion auto-exports to the git-tracked .beads/issues.jsonl — so a
# bad pass is `git revert`-able.
#
# Runner is codex exec (proven hands-off with full hive access). To switch to
# another runtime, set RUNNER below.
#
# Environment:
#   BEADS_DB                — path to the .beads directory (REQUIRED)
#   REPO_DIR                — path to the repo that owns the hive (REQUIRED)
#   CONSOLIDATE_THRESHOLD   — skip if fewer than this many memories (default: 60)
#   CONSOLIDATE_RUNNER      — "codex" or "claude" (default: codex)
#   CONSOLIDATE_DRYRUN      — set to "1" for report-only no-mutation pass
#   WORKFLOW_PATH           — path to consolidation-workflow.md
#                             (default: $HOME/.agent-knowledge/references/consolidation-workflow.md)
#
# Exit codes: 0 = ran or below threshold, 2 = could not measure / bad RUNNER.
set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

: "${BEADS_DB:?Set BEADS_DB to the .beads directory path}"
: "${REPO_DIR:?Set REPO_DIR to the repository root}"
export BEADS_DB

WORKFLOW="${WORKFLOW_PATH:-$HOME/.agent-knowledge/references/consolidation-workflow.md}"
LOG_DIR="${LOG_DIR:-$HOME/.agent-knowledge/metrics/auto-consolidate}"
THRESHOLD="${CONSOLIDATE_THRESHOLD:-60}"
RUNNER="${CONSOLIDATE_RUNNER:-codex}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/run-$(date +%Y%m%d-%H%M%S).log"

notify() {
  # macOS notification; no-op on other platforms
  osascript -e "display notification \"$1\" with title \"Auto-consolidate\"" 2>/dev/null || true
}

# Count from --json, never by grepping human-readable output: a format change
# turns the guard silently into 0. Returns -1 when the measurement itself fails.
mem_count() {
  bd memories --json 2>/dev/null \
    | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(len(d) if isinstance(d,(dict,list)) else 0)
except Exception:
    print(-1)' 2>/dev/null || echo -1
}

COUNT="$(mem_count)"; COUNT="${COUNT##*$'\n'}"; COUNT="${COUNT:-0}"
echo "[$(date)] memory count=$COUNT threshold=$THRESHOLD runner=$RUNNER" | tee -a "$LOG"

# A failed measurement is NOT a pass. Exiting 0 here would recreate the exact bug
# this block replaces.
if [ "$COUNT" -lt 0 ]; then
  echo "[$(date)] WARN: bd memory count UNAVAILABLE (bd memories --json failed) — cannot evaluate threshold; not consolidating" | tee -a "$LOG"
  notify "Auto-consolidate: memory count unavailable — check bd"
  exit 2
fi

if [ "$COUNT" -lt "$THRESHOLD" ]; then
  echo "[$(date)] below threshold — skipping (no consolidation needed)" | tee -a "$LOG"
  exit 0
fi

if [ "${CONSOLIDATE_DRYRUN:-0}" = "1" ]; then
  PROMPT="REPORT-ONLY consolidation dry run. Read ${WORKFLOW}. Analyze the bd hive and produce a report of what you WOULD do: list memories you'd DELETE (key + one-line reason) and insights you'd PROMOTE to which learnings file. Make ZERO changes — no bd forget, no bd remember, no file edits. End with counts: 'would delete N, would promote M'. This is a safety dry run; do not mutate anything."
else
  PROMPT="Run the knowledge consolidation workflow EXACTLY as specified in ${WORKFLOW}. Read that file first and follow every step. This is an UNATTENDED scheduled run, so be conservative: NEVER prune learnings by usage; only delete stale checkpoint/session/superseded records and promote genuinely reusable insights. Run each bd command standalone (no pipes). bd auto-exports on write. When done, update the last-consolidation memory with today's date and counts, and end with a one-line summary."
fi

echo "[$(date)] starting consolidation (runner=$RUNNER)" | tee -a "$LOG"
case "$RUNNER" in
  codex)
    codex exec --skip-git-repo-check --cd "$REPO_DIR" "$PROMPT" >>"$LOG" 2>&1 ;;
  claude)
    ( cd "$REPO_DIR" && claude -p "$PROMPT" --dangerously-skip-permissions >>"$LOG" 2>&1 ) ;;
  *)
    echo "unknown RUNNER=$RUNNER" | tee -a "$LOG"; exit 2 ;;
esac
RC=$?

NEW="$(mem_count)"; NEW="${NEW:-?}"
echo "[$(date)] done rc=$RC  count ${COUNT} -> ${NEW}" | tee -a "$LOG"
notify "Consolidation done: ${COUNT} -> ${NEW} memories (rc=${RC})"
exit 0
