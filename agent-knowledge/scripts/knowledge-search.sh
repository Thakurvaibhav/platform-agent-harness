#!/usr/bin/env bash
# knowledge-search.sh — Search across bd memories + learnings files + domain docs
#
# Usage: knowledge-search.sh <query terms...>
#
# Searches:
#   1. bd memories (key + value text)
#   2. All learnings-*.md files in HARNESS_REFS
#   3. Domain docs in HARNESS_DOCS (if set)
#
# Environment:
#   HARNESS_REFS  — path to the knowledge home's references/ dir
#                   (default: $HOME/.agent-knowledge/references)
#   HARNESS_DOCS  — path to domain docs directory (optional)
#   BEADS_DIR     — beads database location (default: auto-discover)

set -o pipefail

REFS_DIR="${HARNESS_REFS:-$HOME/.agent-knowledge/references}"

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

echo "## Knowledge Search: $QUERY"
echo ""

# --- Section 1: bd memories ---
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
    print("    %s" % (body[:320] + ("\u2026" if len(body) > 320 else "")))
if len(hits) > CAP:
    print()
    print("  ... %d more matches not shown — narrow the query or use: bd memories <keyword>" % (len(hits) - CAP))
'
else
    echo "(bd memories unavailable)"
fi

echo ""

# --- Section 2: learnings files ---
echo "### learnings files"
echo ""
if [ -d "$REFS_DIR" ]; then
    rg -inH --color=never -C1 "$PATTERN" "$REFS_DIR"/learnings-*.md 2>/dev/null | head -60 || echo "(no matches in learnings files)"
else
    echo "(references directory not found at $REFS_DIR)"
fi

echo ""

# --- Section 3: domain docs (optional) ---
if [ -n "${HARNESS_DOCS:-}" ] && [ -d "$HARNESS_DOCS" ]; then
    echo "### domain docs"
    echo ""
    rg -ilH --color=never "$PATTERN" "$HARNESS_DOCS" 2>/dev/null | head -10 || echo "(no matches in domain docs)"
    echo ""
fi
