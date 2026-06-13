#!/usr/bin/env bash
# Statusline: repo, branch, Graphify availability, and bd state (always shown).
#
# Optional segments, each degrades to empty when its inputs are missing:
#   * context-utilization bar  — needs stdin session JSON + python3 + jq plus
#     core/statusline/statusline-context.py (resolved next to this script, or
#     via $STATUSLINE_CONTEXT_PY). 10-char block bar, green/yellow/red at
#     <50 / 50-79 / >=80 %, plus `NN% <tok>k/<max>k`.
#   * kubectl context/namespace `(k8s:<ctx>/<ns>)` — needs `kubectl`.
#
# Pipe the runtime's session-state JSON into stdin for the context indicator;
# with no stdin the line still renders (repo/branch/graphify/bd only). `-e` is
# intentionally omitted so a single missing optional tool never aborts the line.
set -uo pipefail

input="$(cat 2>/dev/null || true)"

script_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
ctx_py="${STATUSLINE_CONTEXT_PY:-$script_dir/statusline-context.py}"

# Working directory: prefer .cwd from session JSON, else $PWD.
cwd="${PWD}"
if [ -n "$input" ] && command -v jq >/dev/null 2>&1; then
  j_cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  [ -n "$j_cwd" ] && cwd="$j_cwd"
fi

branch="$(git --no-optional-locks -C "$cwd" branch --show-current 2>/dev/null || true)"

graph=""
[ -f "$cwd/graphify-out/graph.json" ] && graph=" graphify"

bd_state=""
if command -v bd >/dev/null 2>&1 && [ -d "$cwd/.beads" ]; then
  bd_state=" bd"
fi

# Context-utilization bar (optional; needs stdin JSON + python3 + jq + parser).
ctx_str=""
if [ -n "$input" ] && command -v jq >/dev/null 2>&1 \
   && command -v python3 >/dev/null 2>&1 && [ -f "$ctx_py" ]; then
  ctx_json="$(printf '%s' "$input" | python3 "$ctx_py" 2>/dev/null || true)"
  if [ -n "$ctx_json" ]; then
    pct="$(printf '%s' "$ctx_json" | jq -r '.pct // empty' 2>/dev/null || true)"
    tokens="$(printf '%s' "$ctx_json" | jq -r '.tokens // empty' 2>/dev/null || true)"
    ctx_max="$(printf '%s' "$ctx_json" | jq -r '.ctx_max // empty' 2>/dev/null || true)"
    if [ -n "$pct" ] && [ "$pct" -ge 0 ] 2>/dev/null; then
      if   [ "$pct" -ge 80 ]; then c=31
      elif [ "$pct" -ge 50 ]; then c=33
      else c=32; fi
      tok_h="${tokens:-0}"
      [ "${tokens:-0}" -ge 1000 ] 2>/dev/null && tok_h="$((tokens / 1000))k"
      max_h="?"
      [ -n "$ctx_max" ] && [ "$ctx_max" -gt 0 ] 2>/dev/null && max_h="$((ctx_max / 1000))k"
      bar_len=10
      filled=$(( pct * bar_len / 100 ))
      [ "$filled" -gt "$bar_len" ] && filled=$bar_len
      [ "$filled" -lt 0 ] && filled=0
      empty=$(( bar_len - filled ))
      bar=""
      i=0; while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i+1)); done
      i=0; while [ "$i" -lt "$empty"  ]; do bar="${bar}░"; i=$((i+1)); done
      ctx_str="$(printf ' \033[%sm%s %s%% %s/%s\033[0m' "$c" "$bar" "$pct" "$tok_h" "$max_h")"
    fi
  fi
fi

# kubectl context / namespace (optional; needs kubectl on PATH).
kube=""
if command -v kubectl >/dev/null 2>&1; then
  kctx="$(kubectl config current-context 2>/dev/null || true)"
  if [ -n "$kctx" ]; then
    kns="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)"
    [ -z "$kns" ] && kns="default"
    kube="$(printf ' \033[32m(k8s:%s/%s)\033[0m' "$kctx" "$kns")"
  fi
fi

printf "[%s%s%s]%s%s %s" \
  "$(basename "$cwd")" "${branch:+:$branch}" "$graph$bd_state" "$ctx_str" "$kube" "$ "
