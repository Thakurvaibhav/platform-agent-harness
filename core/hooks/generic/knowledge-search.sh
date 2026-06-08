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
#   HARNESS_REFS  — path to references/ directory (default: ./references)
#   HARNESS_DOCS  — path to domain docs directory (optional)
#   BEADS_DIR     — beads database location (default: auto-discover)

set -o pipefail

REFS_DIR="${HARNESS_REFS:-./references}"

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
BD_OUTPUT=$(bd memories 2>/dev/null || echo "")
if [ -n "$BD_OUTPUT" ]; then
    MATCHES=$(echo "$BD_OUTPUT" | grep -iE "$PATTERN" 2>/dev/null || true)
    if [ -n "$MATCHES" ]; then
        echo "$MATCHES" | head -30
    else
        echo "(no matches in bd memories)"
    fi
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
