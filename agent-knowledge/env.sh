#!/usr/bin/env bash
# env.sh: resolve this machine's harness settings.
#
# Sourced by ~/.zshenv, ~/.bashrc, ~/.bash_profile and by the harness scripts.
# Also runnable: `env.sh --config` prints every setting with where its value came
# from, so a wrong value is visible instead of silent.
#
# THE ESTATE DOES NOT LIVE HERE. This file ships GENERIC defaults only; the real
# values live in config.sh, which is gitignored. A missing config.sh is not an
# error, the generic defaults keep everything working. Copy config.template to
# config.sh and edit that.
#
# Precedence: environment > config.sh > generic default.
#
# EMPTY IS NOT UNSET. ${VAR:-x} treats "" as missing. Every setting below uses
# ${VAR+x}/${VAR-x} tests, so a value deliberately set to "" survives instead of
# being re-defaulted. The three path settings are then rejected on stderr, because
# an empty path is a configuration mistake and deriving from it yields "/" or ".".
# ACTIVE_ORG and TRACKER_BASE_URL are left alone: "" is legitimate for both.
#
# HOW IT IS WIRED
# ---------------
# Source it once from each shell profile that exists:
#     . "$HOME/.agent-knowledge/env.sh"
# and never re-export these variables anywhere else. A raw `export BEADS_DB=` in
# a profile is sourced AFTER this file and silently overrides it.
#
# THE ONE UNAVOIDABLE DUPLICATE
# -----------------------------
# Some runtimes configure the agent's environment from a JSON file, and JSON
# cannot source a shell file. Where a runtime carries a literal copy of BEADS_DB
# (a settings.json `env.BEADS_DB`, for example), that literal must be updated in
# the same edit as the hive path below.

# Resolved BEFORE config.sh, because config.sh is found inside it: HARNESS_HOME
# comes from the environment or the default, never from the config file itself.
export HARNESS_HOME="${HARNESS_HOME:-$HOME/.agent-knowledge}"
HARNESS_CONFIG="${HARNESS_CONFIG-$HARNESS_HOME/config.sh}"

# Sole argument only: a sourced file inherits the caller's positional parameters.
_hc_show=0
if [ "${1-}" = "--config" ] && [ $# -eq 1 ]; then _hc_show=1; fi

# Names spelled out, not held in a variable: zsh (which sources this from ~/.zshenv)
# does not word-split an unquoted parameter, so `for v in $list` would loop once.
_hc_from_env=" "
for _hc_v in WORK_ROOT BEADS_DB HARNESS_DOCS TRACKER_BASE_URL ACTIVE_ORG; do
    # --config reports what a CLEAN shell resolves; the login shell has already
    # exported all five, so every row would otherwise read "environment".
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
        # config.sh assigns plainly and has already clobbered the environment value.
        # Restoring the snapshot is what makes environment > config.sh actually hold.
        *" $1 "*) _hc_src=environment; eval "${1}=\$_hc_env_${1}" ;;
        *) if eval "[ -n \"\${${1}+x}\" ]"; then _hc_src=config; fi ;;
    esac
    eval "if [ -z \"\${${1}+x}\" ]; then ${1}=\$2; fi; export ${1}"
    eval "_hc_val=\$${1}"
    _hc_report="${_hc_report}${1}|${_hc_src}|${_hc_val}
"
}

# Root that holds the git repos and the bd hive.
_hc_set WORK_ROOT "$HOME/Work/git-repos"

# Canonical bd hive. Lives BESIDE the repos, never inside one: a hive nested in a
# repo gets committed by accident and dies with that repo when you change jobs.
# bd does not search for its database; BEADS_DB is the only thing that finds it.
# Derived only from a NON-EMPTY root, because "$WORK_ROOT/.beads" with an empty
# root is "/.beads", which is bd pointed at the filesystem root.
if [ -n "$WORK_ROOT" ]; then
    _hc_set BEADS_DB "$WORK_ROOT/.beads"
else
    _hc_set BEADS_DB ""
fi

# Domain docs tree searched by knowledge-search.sh. Keep it outside WORK_ROOT so
# it survives a repo move.
_hc_set HARNESS_DOCS "$HOME/Work/docs"

# Issue tracker prefix used by the create-pr skill to build ticket links. The
# whole prefix, because trackers disagree on the path: Linear is /issue/<TICKET>,
# Jira is /browse/<TICKET>. No default: consumers omit the link when it is empty.
_hc_set TRACKER_BASE_URL ""

# Active knowledge tier: org short name, lowercase, matching a directory under
# orgs/. INVARIANT: this labels where writes go and must NEVER narrow a read.
# See core/protocols/knowledge-tiers.md.
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
