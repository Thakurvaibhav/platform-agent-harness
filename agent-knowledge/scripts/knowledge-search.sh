#!/usr/bin/env bash
# knowledge-search.sh — search bd memories + both knowledge tiers + reading notes + docs.


# --quiet-weak (KSEARCH_QUIET_WEAK=1) prints NOTHING AT ALL when the best entry covers
# less of the query than BM25_COVERAGE_FLOOR. No-op under SEARCH_BACKEND=ripgrep.

# INVARIANT: the orgs tier is searched UNCONDITIONALLY, with no ACTIVE_ORG filter on
# any read path. Rule, rationale and failure mode: knowledge-tiers.md § ACTIVE_ORG.

# NEVER flip SEARCH_BACKEND to `qmd` without a qmd `orgs` collection: the instance
# tier then vanishes silently.


set -o pipefail

# Hooks and cron do not reliably source a login shell; resolve relative to this file.
_SELF_HOME="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
_HOME_PRESET="${HARNESS_HOME:-}"
# shellcheck source=/dev/null
[ -f "$_SELF_HOME/env.sh" ] && . "$_SELF_HOME/env.sh"

# An explicit HARNESS_HOME wins, else the home this script lives in.
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
# ${VAR-} not ${VAR:-}: an empty HARNESS_DOCS means "no docs tree", and -d skips it.
DOCS_DIR="${HARNESS_DOCS-}"
BEADS_CWD="${BEADS_DIR:-$(cd "$(dirname "${BEADS_DB-}")" 2>/dev/null && pwd || pwd)}"

QUIET_WEAK="${KSEARCH_QUIET_WEAK:-0}"
while [ $# -gt 0 ]; do
    case "$1" in
        --quiet-weak) QUIET_WEAK=1; shift ;;
        --) shift; break ;;
        *) break ;;
    esac
done

if [ $# -eq 0 ]; then
    echo "Usage: knowledge-search.sh [--quiet-weak] <query terms...>"
    echo ""
    echo "Examples:"
    echo "  knowledge-search.sh helm dependency version"
    echo "  knowledge-search.sh strict mTLS health check"
    exit 1
fi

QUERY="$*"
PATTERN=$(echo "$QUERY" | tr ' ' '\n' | sed 's/[^a-zA-Z0-9_-]//g' | paste -sd '|' -)

# A flat `head -N` starves the densest files: rg emits in parallel, arbitrary order.
emit_ranked() {
    local per_file="$1"; shift
    local any=0 f n ranked
    ranked=$(for f in "$@"; do
                 [ -f "$f" ] || continue
                 n=$(rg -ic --color=never "$PATTERN" "$f" 2>/dev/null || echo 0)
                 # if/then, not `[ test ] && printf`: a trailing false test exits
                 # the subshell non-zero under `set -e`.
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
        # No -C1: an entry is one long line, and its leading "N." IS the citation.
        rg -inH --color=never -m "$per_file" "$PATTERN" "$f" 2>/dev/null \
            | sed "s|$HOME_DIR/||" \
            | awk -F: 'BEGIN{OFS=":"}
                 { path=$1; line=$2; $1=""; $2=""; text=substr($0,3);
                   sub(/^references\//,"",path);
                   if (match(text,/^[0-9]+\. /)) {
                     n=substr(text,1,RLENGTH-2);
                     printf "%s#%s  %s\n", path, n, substr(text,RLENGTH+1);
                   } else {
                     printf "%s:%s:%s\n", path, line, text;
                   } }' \
            | cut -c1-240
    done <<< "$ranked"
    [ "$any" = 1 ] || echo "(no matches)"
}

# bm25 ranks ENTRIES, so a hit is already citable; the ripgrep file ranking is also
# the automatic fallback when bm25-search.py is missing.
BM25_MODE=0
BM25_BIN="${HARNESS_SCRIPTS:-$(dirname "$0")}/bm25-search.py"
if [ "${SEARCH_BACKEND:-bm25}" = "bm25" ] && [ -x "$BM25_BIN" ]; then
    BM25_MODE=1
fi

QMD_MODE=0
if [ "${SEARCH_BACKEND:-bm25}" = "qmd" ] && command -v qmd >/dev/null 2>&1; then
    QMD_MODE=1
fi

BM25_COVERAGE_FLOOR="${BM25_COVERAGE_FLOOR:-0.40}"

log_miss() {
    Q="$QUERY" HITS="${1:-0}" COV="${2:-0}" WEAK="${3:-0}" METRICS="$HOME_DIR/metrics" \
        BK="${SEARCH_BACKEND:-default}" python3 - <<'MISSEOF' 2>/dev/null || true
import json, os
rec = {"q": os.environ["Q"], "source": "knowledge-search", "backend": os.environ["BK"],
       "transcript": "", "hits": int(os.environ["HITS"]),
       "coverage": float(os.environ["COV"]), "weak": os.environ["WEAK"] == "1"}
path = os.path.join(os.environ["METRICS"], "search-queries.jsonl")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "a") as fh:
    fh.write(json.dumps(rec) + "\n")
MISSEOF
}

# Ranked BEFORE the first line of output: --quiet-weak must print nothing, title included.
_bm_rows=""; _bm_cov="0"; _bm_hits="0"; _bm_weak=0
if [ "$BM25_MODE" = 1 ] && [ "$QMD_MODE" = 0 ]; then
    _bm=$(HARNESS_HOME="$HOME_DIR" HARNESS_REFS="$REFS_DIR" HARNESS_ORGS="$ORGS_DIR" \
        "$BM25_BIN" --verdict -n "${BM25_HITS:-12}" $QUERY 2>/dev/null) || _bm=""
    if [ -n "$_bm" ]; then
        _bm_cov=$(printf '%s\n' "$_bm" | sed -n '1s/^# coverage=\([0-9.]*\).*/\1/p')
        _bm_hits=$(printf '%s\n' "$_bm" | sed -n '1s/.*hits=\([0-9]*\).*/\1/p')
        _bm_rows=$(printf '%s\n' "$_bm" | tail -n +2)
    fi
    _bm_cov="${_bm_cov:-0}"; _bm_hits="${_bm_hits:-0}"
    _bm_weak=$(awk -v c="$_bm_cov" -v f="$BM25_COVERAGE_FLOOR" 'BEGIN{print (c+0 < f+0) ? 1 : 0}')
    if [ "$_bm_weak" = 1 ]; then
        log_miss "$_bm_hits" "$_bm_cov" 1
        if [ "$QUIET_WEAK" = 1 ]; then exit 0; fi
    fi
fi

echo "## Knowledge Search: $QUERY"
echo ""

# --- Section 6: bd memories, DEFINED here and CALLED LAST (call site at end) ---
bd_memories_section() {
    echo "### bd memories"
    echo ""
    # `bd memories` prints key and body on separate lines, so match whole records.
    BD_JSON=$(cd "$BEADS_CWD" && bd memories --json 2>/dev/null || echo "")
    if [ -z "$BD_JSON" ]; then
        echo "(bd memories unavailable)"
        echo ""
        return 0
    fi
    if [ "$BM25_MODE" = 1 ]; then
        printf '%s' "$BD_JSON" \
            | "$BM25_BIN" --docs-json --pairs -n "${BD_HITS:-25}" $QUERY \
            || echo "(bd ranking failed)"
    else
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
    fi
    echo ""
}

if [ "$QMD_MODE" = 1 ]; then
    echo "### files (qmd)"
    echo ""
    qmd search "$QUERY" --files -n 30 2>/dev/null || echo "(qmd search failed — check collections)"
    echo ""
    # This path returns early, so it needs its own call to keep the hive in the output.
    bd_memories_section
    exit 0
fi

# Lead with the curated index so search REINFORCES it; body matches are the fallback.
echo "### index.md (curated router — start here)"
echo ""
if [ -f "$REFS_DIR/index.md" ]; then
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
    # Score the row's OWN name and prose, never its LINK columns, or a row that merely
    # links to learnings-terraform.md scores a free hit on "terraform".
    own = mm.group(1)
    rest = re.sub(r"\x60[^\x60]*\.(?:md|sh|py|json)\x60", " ", line[mm.end():])
    low = (own + " " + rest).lower()
    hits = sum(1 for x in terms if x.lower() in low)
    if hits:
        rows.append((hits, own))
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

if [ "$BM25_MODE" = 1 ]; then
    echo "### entries, BM25-ranked (both tiers — the citation is the result)"
    echo ""
    if [ "$_bm_weak" = 1 ]; then
        printf "no close match for '%s' (best covers %.0f%%). The rows below are\n" \
            "$QUERY" "$(awk -v c="$_bm_cov" 'BEGIN{print c*100}')"
        echo "the nearest entries, not an answer; treat this as a gap in the corpus"
        echo ""
    fi
    if [ -n "$_bm_rows" ]; then printf '%s\n' "$_bm_rows"; else echo "(bm25 failed)"; fi
    echo ""
        # A file whose list numbering repeats has no citable `#N`, so it is dropped.
    _skipped=$(HARNESS_HOME="$HOME_DIR" HARNESS_REFS="$REFS_DIR" HARNESS_ORGS="$ORGS_DIR" \
        "$BM25_BIN" --skipped 2>/dev/null)
    if [ -n "$_skipped" ]; then
        echo "### unranked files (no citable entries, text match)"
        echo ""
        ( IFS=$'\n'; set -f; emit_ranked 2 $_skipped )
        echo ""
    fi
else
echo "### learnings (project)"
echo ""
if [ -d "$REFS_DIR" ]; then
    emit_ranked 2 "$REFS_DIR"/learnings-*.md
else
    echo "(references directory not found at $REFS_DIR)"
fi

echo ""

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
fi

echo "### reading (external notes)"
echo ""
if [ -d "$READING_DIR" ] && ls "$READING_DIR"/*.md >/dev/null 2>&1; then
    rg -inH --color=never -C1 "$PATTERN" "$READING_DIR"/*.md 2>/dev/null | grep -v "_template.md" | head -40 || echo "(no matches)"
else
    echo "(no reading notes yet — add with the ingest-reading skill)"
fi

echo ""

if [ -d "$DOCS_DIR" ]; then
    echo "### domain docs"
    echo ""
    rg -ilH --color=never "$PATTERN" "$DOCS_DIR" 2>/dev/null | head -10 || echo "(no matches in domain docs)"
    echo ""
fi

bd_memories_section
