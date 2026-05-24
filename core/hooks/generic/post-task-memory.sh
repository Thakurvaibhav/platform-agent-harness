#!/usr/bin/env bash
# Generic post-task memory helper.
#
# Usage: post-task-memory.sh <repo> <prefix> <topic> "<insight>"
#
# Example:
#   post-task-memory.sh myrepo lesson graphify-first \
#     "For architecture questions, query graphify-out/graph.json first."
#
# Calls `bd remember` with a sanitization guard. Prints the resulting key.

set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <repo> <prefix> <topic> \"<insight>\"" >&2
  exit 2
fi

repo="$1"
prefix="$2"
topic="$3"
insight="$4"
key="${repo}/${prefix}/${topic}"

# Reject memories that look like they contain a secret-shaped token.
if printf "%s" "$insight" | grep -E -i '(api[_-]?key|secret|password|bearer|glsa_|ghp_|github_pat_)\s*[:=]?\s*[A-Za-z0-9_./+=-]{8,}' >/dev/null; then
  echo "[harness] refused: insight looks like it contains a secret. Sanitize and retry." >&2
  exit 1
fi

bd remember "$insight" --key "$key"
echo "[harness] stored memory: $key"
