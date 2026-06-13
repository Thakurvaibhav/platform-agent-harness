#!/usr/bin/env bash
# learn.sh — one-liner to persist a learning without ceremony.
#
# Usage:
#   learn.sh "<insight>"                          # key defaults to session/adhoc
#   learn.sh "<insight>" <domain>/<category>/<topic>
#
# Resolves where to run `bd remember`:
#   1. Walk up from CWD to the first dir that owns a .beads database.
#   2. Else fall back to $BEADS_DIR if it is set and exists.
#   3. Else run `bd remember` in the current directory.
#
# Lower friction = it actually happens. Capture on discovery, not at task end.

set -o pipefail

INSIGHT="$1"
KEY="${2:-session/adhoc}"

if [ -z "$INSIGHT" ]; then
  echo "usage: learn.sh \"<insight>\" [<domain>/<category>/<topic>]" >&2
  exit 2
fi

find_bd_cwd() {
  local dir; dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    [ -d "$dir/.beads" ] && { echo "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  if [ -n "${BEADS_DIR:-}" ] && [ -d "$BEADS_DIR/.beads" ]; then
    echo "$BEADS_DIR"; return 0
  fi
  return 1
}

BD_CWD="$(find_bd_cwd)"
if [ -n "$BD_CWD" ]; then
  ( cd "$BD_CWD" && bd remember "$INSIGHT" --key "$KEY" )
else
  bd remember "$INSIGHT" --key "$KEY"
fi
