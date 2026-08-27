#!/usr/bin/env bash
# drift-check.sh — Detect staleness in the knowledge harness
#
# Run at session start/resume. Outputs warnings for:
#   FRESHNESS:
#   1. Stale graphify graph (>7 days behind latest commit)
#   2. Learnings files not updated despite recent repo activity
#   3. bd memory bloat (>60 memories)
#   4. Consolidation overdue (>7 days)
#   CONSISTENCY (cross-reference integrity, not just age):
#   5. Learnings file exists but is not indexed in index.md (discovery gap)
#   6. index.md references a learnings file that does not exist (dangling)
#   7. Asymmetric cross-ref: A's "See also:" lists B, but B does not list A back
#
# Exit codes: 0 = clean, 1 = warnings found (non-blocking)

set -o pipefail

REFS_DIR="${HARNESS_REFS:-$HOME/.agent-knowledge/references}"
# Repo whose .beads hive the memory/consolidation checks read from.
INFRA_DIR="${HARNESS_REPO:-$HOME/repos/infra}"
WARNINGS=()

# --- Helper: get file mtime as epoch ---
file_mtime() {
    /usr/bin/stat -f %m "$1" 2>/dev/null
}

# --- 1. Graphify freshness ---
check_graph_freshness() {
    local repo_dir="$1"
    local repo_name="$(basename "$repo_dir")"
    local graph="$repo_dir/graphify-out/graph.json"

    if [ ! -f "$graph" ]; then
        WARNINGS+=("DRIFT: $repo_name has no graphify graph (graphify-out/graph.json missing)")
        return
    fi

    local graph_mtime
    graph_mtime=$(file_mtime "$graph")
    local now
    now=$(date +%s)
    local graph_age_days=$(( (now - graph_mtime) / 86400 ))

    if [ "$graph_age_days" -gt 7 ]; then
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

    # mtime is a weak staleness proxy — a correct, stable file needs no edits. Only flag
    # genuine abandonment, so this stays signal rather than a recurring session-start warning.
    if [ "$oldest_days" -gt 120 ]; then
        WARNINGS+=("DRIFT: $oldest_file not updated in ${oldest_days}d — check it is still accurate")
    fi
}

# --- 3. Memory bloat ---
check_memory_count() {
    local count
    # Count from --json, never by grepping human-readable output: a format change
    # silently returns 0, and a check that can only under-report reads as a pass.
    count=$(cd "$INFRA_DIR" 2>/dev/null && bd memories --json 2>/dev/null \
            | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(len(d) if isinstance(d,(dict,list)) else 0)
except Exception:
    print(-1)' 2>/dev/null || echo -1)
    count="${count##*$'\n'}"  # take last line if multi-line
    count="${count:-0}"
    # -1 means the measurement itself failed. Say so rather than passing silently:
    # a check that could not run must never render as a pass.
    if [ "$count" -lt 0 ]; then
        WARNINGS+=("DRIFT: bd memory count UNAVAILABLE (bd memories --json failed) — bloat check did not run")
        return
    fi
    if [ "$count" -gt 60 ]; then
        WARNINGS+=("DRIFT: $count bd memories (threshold: 60). Consider running /consolidate")
    fi
}

# --- 4. Consolidation overdue ---
check_consolidation_freshness() {
    local last_consol
    # Anchor to the canonical `meta/last-consolidation` memory — `bd memories consolidation`
    # fuzzy-matches ANY memory containing "consolidation", so a bare date|head -1 grabs the
    # first date from an unrelated memory. Pin to the key's content line.
    last_consol=$(cd "$INFRA_DIR" 2>/dev/null && bd memories consolidation 2>/dev/null | grep -A1 "meta/last-consolidation" | grep -oE "[0-9]{4}-[0-9]{2}-[0-9]{2}" | head -1 || echo "")
    if [ -z "$last_consol" ]; then
        WARNINGS+=("DRIFT: No consolidation ever recorded. Run /consolidate")
        return
    fi

    local consol_epoch
    consol_epoch=$(python3 -c "from datetime import datetime; print(int(datetime.strptime('$last_consol','%Y-%m-%d').timestamp()))" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    local days_since=$(( (now - consol_epoch) / 86400 ))

    if [ "$days_since" -gt 7 ]; then
        WARNINGS+=("DRIFT: Last consolidation was ${days_since}d ago ($last_consol). Consider /consolidate")
    fi
}

# --- 5-7. Reference consistency (index integrity + cross-ref symmetry) ---
check_reference_consistency() {
    local index="$REFS_DIR/index.md"
    [ -f "$index" ] || { WARNINGS+=("DRIFT: index.md missing at $index"); return; }

    # 5. Every learnings-*.md on disk is referenced in index.md
    for f in "$REFS_DIR"/learnings-*.md; do
        [ -f "$f" ] || continue
        local base; base="$(basename "$f")"
        grep -q "$base" "$index" || WARNINGS+=("DRIFT: $base exists but is not indexed in index.md (discovery gap)")
    done

    # 6. Every learnings-*.md named in index.md exists on disk
    local ref
    for ref in $(grep -oE 'learnings-[a-z0-9-]+\.md' "$index" | sort -u); do
        [ -f "$REFS_DIR/$ref" ] || WARNINGS+=("DRIFT: index.md references $ref but the file does not exist (dangling)")
    done

    # 7. "See also:" cross-ref symmetry — if A lists B, B should list A
    for f in "$REFS_DIR"/learnings-*.md; do
        [ -f "$f" ] || continue
        local a; a="$(basename "$f")"
        local seealso; seealso="$(grep -m1 -i 'See also:' "$f")"
        [ -n "$seealso" ] || continue
        local b
        for b in $(printf '%s' "$seealso" | grep -oE 'learnings-[a-z0-9-]+\.md' | sort -u); do
            [ "$b" = "$a" ] && continue
            [ -f "$REFS_DIR/$b" ] || continue
            # does B's See-also line reference A back?
            grep -m1 -i 'See also:' "$REFS_DIR/$b" | grep -q "$a" \
                || WARNINGS+=("DRIFT: cross-ref asymmetry — $a lists $b, but $b's 'See also:' omits $a")
        done
    done
}

# --- Run all checks ---
# 8. Every engineering agent routes to the canonical code-quality standard.
# A rule that never reaches the agent is the most common way standards fail —
# so the routing itself is asserted, not assumed.
check_standard_routing() {
    local std="$REFS_DIR/code-quality.md"
    local agents_dir="$HOME/.claude/agents"
    [ -f "$std" ] || { WARNINGS+=("DRIFT: code-quality.md missing at $std"); return; }
    [ -d "$agents_dir" ] || return

    # Read-only / non-engineering agents legitimately skip it.
    local skip="alert-investigator task-planner tool-researcher"
    local f base
    for f in "$agents_dir"/*.md; do
        [ -f "$f" ] || continue
        base="$(basename "$f" .md)"
        case " $skip " in *" $base "*) continue ;; esac
        grep -q "code-quality.md" "$f" \
            || WARNINGS+=("DRIFT: agent '$base' does not reference code-quality.md (standard will not reach it)")
    done

    grep -q "code-quality.md" "$HOME/.claude/AGENTS.md" 2>/dev/null \
        || WARNINGS+=("DRIFT: Fox AGENTS.md does not reference code-quality.md")
    grep -q "code-quality.md" "$HOME/.agent-knowledge/scripts/codex-dispatch.sh" 2>/dev/null \
        || WARNINGS+=("DRIFT: codex-dispatch.sh preamble does not name code-quality.md (Codex workers get no standard)")
}

check_learnings_freshness
check_memory_count
check_consolidation_freshness
check_reference_consistency
check_standard_routing

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
