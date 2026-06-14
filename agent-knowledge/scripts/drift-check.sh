#!/usr/bin/env bash
# drift-check.sh — Detect staleness in the knowledge harness
#
# Run at session start/resume. Outputs warnings for:
#   1. Stale graphify graph (>7 days behind latest commit)
#   2. Learnings files not updated despite recent activity
#   3. bd memory bloat (>60 memories)
#   4. Consolidation overdue (>7 days)
#
# Environment:
#   HARNESS_REFS        — path to the knowledge home's references/ dir
#                         (default: $HOME/.agent-knowledge/references)
#   HARNESS_REPOS       — space-separated list of repo paths to check graphs for
#   DRIFT_GRAPH_DAYS    — graph staleness threshold in days (default: 7)
#   DRIFT_LEARN_DAYS    — learnings staleness threshold in days (default: 30)
#   DRIFT_MEMORY_MAX    — memory count threshold (default: 60)
#   DRIFT_CONSOL_DAYS   — consolidation overdue threshold in days (default: 7)
#
# Exit codes: 0 = clean, 1 = warnings found (non-blocking)

set -o pipefail

REFS_DIR="${HARNESS_REFS:-$HOME/.agent-knowledge/references}"
REPOS="${HARNESS_REPOS:-$(pwd)}"
GRAPH_DAYS="${DRIFT_GRAPH_DAYS:-7}"
LEARN_DAYS="${DRIFT_LEARN_DAYS:-30}"
MEMORY_MAX="${DRIFT_MEMORY_MAX:-60}"
CONSOL_DAYS="${DRIFT_CONSOL_DAYS:-7}"
WARNINGS=()

# --- Helper: get file mtime as epoch (macOS + Linux) ---
file_mtime() {
    if [ "$(uname)" = "Darwin" ]; then
        /usr/bin/stat -f %m "$1" 2>/dev/null
    else
        stat -c %Y "$1" 2>/dev/null
    fi
}

# --- 1. Graphify freshness ---
check_graph_freshness() {
    local repo_dir="$1"
    local repo_name
    repo_name="$(basename "$repo_dir")"
    local graph="$repo_dir/graphify-out/graph.json"

    if [ ! -f "$graph" ]; then
        return
    fi

    local graph_mtime
    graph_mtime=$(file_mtime "$graph")
    local now
    now=$(date +%s)
    local graph_age_days=$(( (now - graph_mtime) / 86400 ))

    if [ "$graph_age_days" -gt "$GRAPH_DAYS" ]; then
        local commits_since
        commits_since=$(cd "$repo_dir" && git log --oneline --since="@${graph_mtime}" 2>/dev/null | wc -l | tr -d ' ')
        if [ "${commits_since:-0}" -gt 5 ]; then
            WARNINGS+=("DRIFT: $repo_name graph is ${graph_age_days}d old with $commits_since commits since last build. Run: cd $repo_dir && graphify . --update")
        fi
    fi
}

# --- 2. Learnings staleness ---
check_learnings_freshness() {
    if [ ! -d "$REFS_DIR" ]; then return; fi

    local oldest_file=""
    local oldest_days=0
    local now
    now=$(date +%s)

    for f in "$REFS_DIR"/learnings-*.md; do
        [ -f "$f" ] || continue
        local mtime
        mtime=$(file_mtime "$f")
        local age_days=$(( (now - mtime) / 86400 ))
        if [ "$age_days" -gt "$oldest_days" ]; then
            oldest_days=$age_days
            oldest_file="$(basename "$f")"
        fi
    done

    if [ "$oldest_days" -gt "$LEARN_DAYS" ]; then
        WARNINGS+=("DRIFT: $oldest_file not updated in ${oldest_days}d — may have stale entries")
    fi
}

# --- 3. Memory bloat ---
check_memory_count() {
    local count
    count=$(bd memories 2>/dev/null | grep -c "^### " 2>/dev/null || true)
    count="${count##*$'\n'}"
    count="${count:-0}"
    if [ "$count" -gt "$MEMORY_MAX" ]; then
        WARNINGS+=("DRIFT: $count bd memories (threshold: $MEMORY_MAX). Consider running /consolidate")
    fi
}

# --- 4. Consolidation overdue ---
check_consolidation_freshness() {
    local last_consol
    last_consol=$(bd memories consolidation 2>/dev/null | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}" | head -1 || echo "")
    if [ -z "$last_consol" ]; then
        WARNINGS+=("DRIFT: No consolidation ever recorded. Run /consolidate")
        return
    fi

    local consol_epoch
    consol_epoch=$(python3 -c "from datetime import datetime; print(int(datetime.strptime('$last_consol','%Y-%m-%d').timestamp()))" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    local days_since=$(( (now - consol_epoch) / 86400 ))

    if [ "$days_since" -gt "$CONSOL_DAYS" ]; then
        WARNINGS+=("DRIFT: Last consolidation was ${days_since}d ago ($last_consol). Consider /consolidate")
    fi
}

# --- Run all checks ---
for repo in $REPOS; do
    [ -d "$repo" ] && check_graph_freshness "$repo"
done
check_learnings_freshness
check_memory_count
check_consolidation_freshness

# --- Output ---
if [ ${#WARNINGS[@]} -eq 0 ]; then
    echo "Harness health: all clear"
    exit 0
else
    echo "## Harness Drift Warnings (${#WARNINGS[@]})"
    echo ""
    for w in "${WARNINGS[@]}"; do
        echo "- $w"
    done
    exit 1
fi
