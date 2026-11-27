#!/usr/bin/env bash
# learn.sh: one-liner to persist a learning without ceremony.
#
# Usage:
#   learn.sh "<insight>"                          # bd derives the key from the content
#   learn.sh "<insight>" <domain>/<category>/<topic>
#
# Resolves where to run `bd remember`:
#   1. Walk up from CWD to the first dir that owns a .beads database.
#   2. Else fall back to the directory holding $BEADS_DB, which env.sh owns.
#   3. Else run `bd remember` in the current directory.
#
# Lower friction = it actually happens. Capture on discovery, not at task end.

set -o pipefail

# Hooks and cron do not reliably source a login shell, so pick up this machine's
# paths here rather than assuming the caller's environment already has them.
# Resolved relative to this script so the home can live anywhere.
_SELF_HOME="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
# shellcheck source=/dev/null
[ -f "$_SELF_HOME/env.sh" ] && . "$_SELF_HOME/env.sh"

INSIGHT="$1"
KEY="${2:-}"

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
  # ${VAR-} not ${VAR:-}: with no hive configured the -d test fails and the caller
  # falls back to running bd in CWD, which is the honest degradation.
  local hive="${BEADS_DB-}"
  [ -d "$hive" ] && { dirname "$hive"; return 0; }
  return 1
}

# No key given: omit --key so bd derives one from the content. Defaulting to a
# fixed key made every keyless call overwrite the previous memory in place --
# `bd remember --key` updates an existing key rather than adding one.
KEY_ARG=()
[ -n "$KEY" ] && KEY_ARG=(--key "$KEY")

BD_CWD="$(find_bd_cwd)"
if [ -n "$BD_CWD" ]; then
  ( cd "$BD_CWD" && bd remember "$INSIGHT" "${KEY_ARG[@]}" )
else
  bd remember "$INSIGHT" "${KEY_ARG[@]}"
fi
