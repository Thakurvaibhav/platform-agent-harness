#!/usr/bin/env bash
# Harness settings. `env.sh --config` prints every setting and where it came from.


# ${VAR+x}/${VAR-x} throughout, never ${VAR:-}: "" and unset differ here, and an
# empty value set on purpose must survive.

# A raw `export BEADS_DB=` in a profile is sourced AFTER this file and wins.

# Where a runtime configures the agent from JSON (a settings.json `env.BEADS_DB`),
# that literal copy must be updated in the same edit as the hive path below.

# Resolved BEFORE config.sh, which is found inside it, so never from config.sh.
export HARNESS_HOME="${HARNESS_HOME:-$HOME/.agent-knowledge}"
HARNESS_CONFIG="${HARNESS_CONFIG-$HARNESS_HOME/config.sh}"

# Sole argument only: a sourced file inherits the caller's positional parameters.
_hc_show=0
if [ "${1-}" = "--config" ] && [ $# -eq 1 ]; then _hc_show=1; fi

# Names spelled out, not in a variable: zsh does not word-split, so `for v in $list` loops once.
_hc_from_env=" "
for _hc_v in WORK_ROOT BEADS_DB HARNESS_DOCS TRACKER_BASE_URL ACTIVE_ORG; do
    # --config must report what a CLEAN shell resolves; the login shell exported all five.
    if [ "$_hc_show" = 1 ]; then unset "$_hc_v"; fi
    # if/then not `[ ] && x`: a trailing false test kills a caller under set -e.
    if eval "[ -n \"\${${_hc_v}+x}\" ]"; then
        _hc_from_env="${_hc_from_env}${_hc_v} "
        eval "_hc_env_${_hc_v}=\$${_hc_v}"
    fi
done

_hc_state=absent
if [ -f "$HARNESS_CONFIG" ]; then
    _hc_state=present
    . "$HARNESS_CONFIG"
fi

_hc_report=""
_hc_set() {   # _hc_set <VAR> <generic default>
    _hc_src=default
    case "$_hc_from_env" in
        # config.sh has clobbered the env value; this restore is what makes it lose.
        *" $1 "*) _hc_src=environment; eval "${1}=\$_hc_env_${1}" ;;
        *) if eval "[ -n \"\${${1}+x}\" ]"; then _hc_src=config; fi ;;
    esac
    eval "if [ -z \"\${${1}+x}\" ]; then ${1}=\$2; fi; export ${1}"
    eval "_hc_val=\$${1}"
    _hc_report="${_hc_report}${1}|${_hc_src}|${_hc_val}
"
}

_hc_set WORK_ROOT "$HOME/Work/git-repos"

# An empty root would derive "/.beads": bd pointed at the filesystem root.
if [ -n "$WORK_ROOT" ]; then
    _hc_set BEADS_DB "$WORK_ROOT/.beads"
else
    _hc_set BEADS_DB ""
fi

_hc_set HARNESS_DOCS "$HOME/Work/docs"

_hc_set TRACKER_BASE_URL ""

# INVARIANT: labels where writes go, never narrows a read (knowledge-tiers.md).
_hc_set ACTIVE_ORG ""

for _hc_v in WORK_ROOT BEADS_DB HARNESS_DOCS; do
    if ! eval "[ -n \"\$${_hc_v}\" ]"; then
        printf 'env.sh: %s is set but empty (check %s)\n' "$_hc_v" "$HARNESS_CONFIG" >&2
    fi
done

if [ "$_hc_show" = 1 ]; then
    printf 'config file: %s (%s)\n\n' "$HARNESS_CONFIG" "$_hc_state"
    printf '  %-18s %-12s %s\n' "HARNESS_HOME" "pre-config" "$HARNESS_HOME"
    printf '%s' "$_hc_report" | while IFS='|' read -r _hc_n _hc_s _hc_x; do
        printf '  %-18s %-12s %s\n' "$_hc_n" "$_hc_s" "$_hc_x"
    done
    printf '\nprecedence: environment > config.sh > generic default\n'
fi

unset _hc_v _hc_from_env _hc_state _hc_report _hc_src _hc_val _hc_show
unset _hc_env_WORK_ROOT _hc_env_BEADS_DB _hc_env_HARNESS_DOCS \
      _hc_env_TRACKER_BASE_URL _hc_env_ACTIVE_ORG
unset -f _hc_set
