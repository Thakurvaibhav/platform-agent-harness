#!/usr/bin/env bash
# knowledge-search.sh — Search across bd memories + both knowledge tiers + reading notes + docs
#
# Usage: knowledge-search.sh <query terms...>
#
# Searches:
#   1. bd memories (key + value text)                — always ripgrep
#   2. references/index.md                           — CURATED router, ranked by distinct terms
#   3. references/learnings-*.md                     — PORTABLE tier (method, vendor behavior)
#   4. orgs/*/*.md                                   — INSTANCE tier, EVERY org, always
#   5. reading/*.md                                  — external notes, separate trust tier
#   6. $HARNESS_DOCS                                 — domain docs (optional)
#
# Sections 3 and 4 rank files by match count and print the ranking before any match
# lines: the ranking is the routing signal, the lines are only proof. See emit_ranked.
#
# INVARIANT: the orgs tier is searched UNCONDITIONALLY — no ACTIVE_ORG filter on any
# read path. Rule, rationale, and failure mode: knowledge-tiers.md § ACTIVE_ORG.
#
# Environment:
#   HARNESS_HOME  — deployed knowledge home (default: $HOME/.agent-knowledge)
#   HARNESS_REFS  — portable tier   (default: $HARNESS_HOME/references)
#   HARNESS_ORGS  — instance tier   (default: $HARNESS_HOME/orgs)
#   HARNESS_READING — reading notes (default: $HARNESS_HOME/reading)
#   HARNESS_DOCS  — domain docs directory (optional)
#   BEADS_DIR     — beads database location (default: auto-discover)
#
# Backend seam: SEARCH_BACKEND=qmd (bd memories stay ripgrep). NEVER flip without
# a qmd `orgs` collection — the instance tier vanishes silently. knowledge-tiers.md.

set -o pipefail

# Hooks and cron do not reliably source a login shell, so pick up this machine's
# paths here rather than assuming the caller's environment already has them.
# Resolved relative to this script so the home can live anywhere.
_SELF_HOME="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
_HOME_PRESET="${HARNESS_HOME:-}"
# shellcheck source=/dev/null
[ -f "$_SELF_HOME/env.sh" ] && . "$_SELF_HOME/env.sh"

# An explicit HARNESS_HOME from the caller wins; otherwise the home this script
# lives in beats env.sh's default, so a checkout in any location searches itself.
if [ -n "$_HOME_PRESET" ]; then
    HOME_DIR="$_HOME_PRESET"
elif [ -d "$_SELF_HOME/references" ]; then
    HOME_DIR="$_SELF_HOME"
else
    HOME_DIR="${HARNESS_HOME:-$HOME/.agent-knowledge}"
fi
REFS_DIR="${HARNESS_REFS:-$HOME_DIR/references}"
ORGS_DIR="${HARNESS_ORGS:-$HOME_DIR/orgs}"
READING_DIR="${HARNESS_READING:-$HOME_DIR/reading}"

if [ $# -eq 0 ]; then
    echo "Usage: knowledge-search.sh <query terms...>"
    echo ""
    echo "Examples:"
    echo "  knowledge-search.sh helm dependency version"
    echo "  knowledge-search.sh strict mTLS health check"
    exit 1
fi

QUERY="$*"
PATTERN=$(echo "$QUERY" | tr ' ' '\n' | sed 's/[^a-zA-Z0-9_-]//g' | paste -sd '|' -)

# A flat `head -N` over a multi-file match stream STARVES the densest files: rg walks
# files in parallel, so emission order is arbitrary AND non-deterministic, and one
# verbose file can swallow the whole budget. Measured on a 4-term query: 782 matching
# lines across the instance tier, of which the 60 kept gave ONE file 52 lines while the
# file with the MOST matches (126) got 2 — the most relevant file was effectively
# invisible. Rank files by match count, print the ranking (that list is the routing
# signal), then sample a bounded number of lines per file as proof.
emit_ranked() {
    local per_file="$1"; shift
    local any=0 f n ranked
    ranked=$(for f in "$@"; do
                 [ -f "$f" ] || continue
                 n=$(rg -ic --color=never "$PATTERN" "$f" 2>/dev/null || echo 0)
                 # if/then, not `[ test ] && printf`: as the last command in the loop a
                 # false test makes the subshell exit non-zero, which kills the whole
                 # script the moment anyone adds `set -e` to this file.
                 if [ "${n:-0}" -gt 0 ]; then printf '%s\t%s\n' "$n" "$f"; fi
             done | sort -rn || true)
    if [ -z "$ranked" ]; then echo "(no matches)"; return; fi
    echo "matching files, densest first — open the ones your task overlaps:"
    while IFS=$'\t' read -r n f; do
        [ -n "$f" ] || continue
        printf '  %4s matches  %s\n' "$n" "${f##*/}"
    done <<< "$ranked"
    echo ""
    while IFS=$'\t' read -r n f; do
        [ -n "$f" ] || continue
        any=1
        # No -C1: an entry is already ONE long line, so context triples a 1-2KB line.
        # Truncate too — the ranking above routes; these lines only prove the hit.
        rg -inH --color=never -m "$per_file" "$PATTERN" "$f" 2>/dev/null \
            | cut -c1-240 | sed "s|$HOME_DIR/||"
    done <<< "$ranked"
    [ "$any" = 1 ] || echo "(no matches)"
}

# Decide file-search backend.
QMD_MODE=0
if [ "${SEARCH_BACKEND:-ripgrep}" = "qmd" ] && command -v qmd >/dev/null 2>&1; then
    QMD_MODE=1
fi

echo "## Knowledge Search: $QUERY"
echo ""

# --- Section 1: bd memories (always ripgrep) ---
echo "### bd memories"
echo ""
# `bd memories` prints key and body on separate lines, so a line-wise grep
# returns one or the other. Match whole records instead.
BD_JSON=$(bd memories --json 2>/dev/null || echo "")
if [ -n "$BD_JSON" ]; then
    printf '%s' "$BD_JSON" | PATTERN="$PATTERN" /usr/bin/python3 -c '
import json, os, re, sys
try: d = json.load(sys.stdin)
except Exception: print("(bd memories unreadable)"); raise SystemExit
items = d.items() if isinstance(d, dict) else [(m.get("key"), m.get("content","")) for m in d]
rx = re.compile(os.environ["PATTERN"], re.I)
hits = [(k, str(v)) for k, v in items if k and (rx.search(k) or rx.search(str(v)))]
if not hits:
    print("(no matches in bd memories)"); raise SystemExit
CAP = 25
for k, body in hits[:CAP]:
    body = " ".join(body.split())
    print("  %s" % k)
    print("    %s" % (body[:320] + ("…" if len(body) > 320 else "")))
if len(hits) > CAP:
    print()
    print("  ... %d more matches not shown — narrow the query or use: bd memories <keyword>" % (len(hits) - CAP))
'
else
    echo "(bd memories unavailable)"
fi

echo ""

# --- Sections 2-6: files (qmd if enabled, else ripgrep per-source) ---
if [ "$QMD_MODE" = 1 ]; then
    echo "### files (qmd)"
    echo ""
    qmd search "$QUERY" --files -n 30 2>/dev/null || echo "(qmd search failed — check collections)"
    echo ""
    exit 0
fi

# --- Section 2: the curated router ---
# index.md's Keywords columns are hand-maintained and are the whole point of the
# two-tier system, yet a raw grep over file BODIES bypasses them: a keyword that is an
# intent hook ("pod debugging") rather than a literal string in the text routed nothing.
# Lead with the index so search REINFORCES it instead of competing with it; the ranked
# body matches below are the fallback, not the route.
echo "### index.md (curated router — start here)"
echo ""
if [ -f "$REFS_DIR/index.md" ]; then
    # Rank a row by how many DISTINCT query terms it matches, not by whether any single
    # one does: an OR match on one generic word ("limit") is not routing.
    _idx=$(QP="$PATTERN" python3 - "$REFS_DIR/index.md" <<'PYEOF'
import os, re, sys
terms = list(dict.fromkeys(x for x in os.environ["QP"].split("|") if x))
rows = []
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.startswith("| "):
        continue
    # \x60 is a backtick: bash 3.2 parses literal backticks inside this heredoc as
    # command substitution and dies on the unmatched one (macOS /bin/bash).
    mm = re.match(r"\| *\[?\x60([^\x60]+)\x60", line)
    if not mm:
        continue
    low = line.lower()
    hits = sum(1 for x in terms if x.lower() in low)
    if hits:
        rows.append((hits, mm.group(1)))
rows.sort(key=lambda r: (-r[0], r[1]))
best = rows[0][0] if rows else 0
for h, f in rows[:8]:
    if h == best or h >= 2:
        print("  %d/%d terms  %s" % (h, len(terms), f))
PYEOF
) || true
    if [ -n "$_idx" ]; then
        echo "index rows matching the MOST query terms — the curated answer:"
        printf '%s\n' "$_idx"
    else
        echo "(no index row matched — body matches below are unrouted; if one is"
        echo " relevant, its index keywords are missing and should be added)"
    fi
else
    echo "(no index.md at $REFS_DIR — the curated router is missing)"
fi

echo ""

# --- Section 3: portable tier ---
echo "### learnings (project)"
echo ""
if [ -d "$REFS_DIR" ]; then
    emit_ranked 2 "$REFS_DIR"/learnings-*.md
else
    echo "(references directory not found at $REFS_DIR)"
fi

echo ""

# --- Section 4: instance tier — every org, unconditionally (see header) ---
# Guard with -d: an unmatched glob expands to its literal pattern, not to nothing.
if [ -d "$ORGS_DIR" ]; then
    _found_org=0
    for _org_path in "$ORGS_DIR"/*/; do
        [ -d "$_org_path" ] || continue
        _org=$(basename "$_org_path")
        ls "$_org_path"*.md >/dev/null 2>&1 || continue
        _found_org=1
        if [ "$_org" = "${ACTIVE_ORG:-}" ]; then
            echo "### org: $_org (instance knowledge — ACTIVE)"
        else
            echo "### org: $_org (instance knowledge)"
        fi
        echo ""
        emit_ranked 2 "$_org_path"*.md
        echo ""
    done
    if [ "$_found_org" = 0 ]; then
        echo "### orgs (instance knowledge)"
        echo ""
        echo "(no org knowledge yet — create $ORGS_DIR/<org>/)"
        echo ""
    fi
else
    echo "### orgs (instance knowledge)"
    echo ""
    echo "(no orgs dir at $ORGS_DIR — nothing to search)"
    echo ""
fi

# --- Section 5: reading notes (separate trust tier) ---
echo "### reading (external notes)"
echo ""
if [ -d "$READING_DIR" ] && ls "$READING_DIR"/*.md >/dev/null 2>&1; then
    rg -inH --color=never -C1 "$PATTERN" "$READING_DIR"/*.md 2>/dev/null | grep -v "_template.md" | head -40 || echo "(no matches)"
else
    echo "(no reading notes yet — add with the ingest-reading skill)"
fi

echo ""

# --- Section 6: domain docs (optional) ---
if [ -n "${HARNESS_DOCS:-}" ] && [ -d "$HARNESS_DOCS" ]; then
    echo "### domain docs"
    echo ""
    rg -ilH --color=never "$PATTERN" "$HARNESS_DOCS" 2>/dev/null | head -10 || echo "(no matches in domain docs)"
    echo ""
fi
