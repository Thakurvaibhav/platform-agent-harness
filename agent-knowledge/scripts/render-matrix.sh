#!/usr/bin/env bash
# render-matrix.sh — render a chart against every environment values file, in
# parallel, and diff each against the merge-base. Emits one row per environment.
#
# This is the offline proof R1 asks for, at fleet width. A source diff does not
# tell you what a values change does on 15 environments; this does.
#
# Deterministic work, so it fans out with shell jobs rather than agents — an LLM
# worker per `helm template` would be slower and no more correct. That is the
# general dispatch heuristic: fan out judgment, not commands.
#
# Usage:
#   render-matrix.sh <chart-dir> [base-ref]      # default base: origin/main
#   render-matrix.sh charts/my-chart
#
# Per-environment values are expected at <chart-dir>/values/*.yaml. If your repo
# nests them one level deeper (e.g. values/envs/, values/clusters/), point
# RENDER_VALUES_DIR at that directory:
#   RENDER_VALUES_DIR=charts/my-chart/values/envs render-matrix.sh charts/my-chart
#
# Env: RENDER_JOBS (default 8) · RENDER_VALUES_DIR (default <chart-dir>/values)
#
# Exit: 0 rendered, 1 a render failed, 2 usage.
set -uo pipefail

CHART="${1:?usage: render-matrix.sh <chart-dir> [base-ref]}"
BASE_REF="${2:-origin/main}"
CHART="${CHART%/}"
NAME="$(basename "$CHART")"
JOBS="${RENDER_JOBS:-8}"

command -v helm >/dev/null || { echo "helm not on PATH" >&2; exit 2; }
[ -d "$CHART" ] || { echo "no such chart dir: $CHART" >&2; exit 2; }

VALUES_DIR="${RENDER_VALUES_DIR:-$CHART/values}"
VALUES_DIR="${VALUES_DIR%/}"
[ -d "$VALUES_DIR" ] || { echo "no per-environment values under $VALUES_DIR — nothing to fan out (set RENDER_VALUES_DIR)" >&2; exit 2; }

WORK="$(mktemp -d)"; BASE_TREE="$WORK/base"
cleanup() { git worktree remove --force "$BASE_TREE" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

BASE_SHA="$(git merge-base "$BASE_REF" HEAD 2>/dev/null || echo "$BASE_REF")"
git worktree add -d "$BASE_TREE" "$BASE_SHA" >/dev/null 2>&1 \
  || { echo "could not create base worktree at $BASE_SHA" >&2; exit 2; }

# Subcharts must exist in BOTH trees or the base renders empty and every
# environment reports "new" — a verdict derived from a render that never happened.
helm dep build "$CHART"            >/dev/null 2>&1
helm dep build "$BASE_TREE/$CHART" >/dev/null 2>&1
BASE_OK=1
[ -d "$BASE_TREE/$CHART" ] || BASE_OK=0

# One render pair per environment. Redirect to a file — never pipe a large render
# through a hook-wrapped command (rtk and friends); it truncates and the loss is silent.
render_one() {
  local env_name="$1" vals="$2"
  local head_out="$WORK/$env_name.head" base_out="$WORK/$env_name.base"
  helm template "$NAME" "$CHART" -f "$vals" > "$head_out" 2>"$WORK/$env_name.err"
  local rc_head=$?
  local base_rc=0
  if [ -f "$BASE_TREE/$vals" ]; then
    helm template "$NAME" "$BASE_TREE/$CHART" -f "$BASE_TREE/$vals" > "$base_out" 2>/dev/null || base_rc=1
  else
    : > "$base_out"; base_rc=2   # values file genuinely new on this branch
  fi
  if [ $rc_head -ne 0 ]; then
    printf '%s\tRENDER-FAIL\t-\t-\t%s\n' "$env_name" "$(head -1 "$WORK/$env_name.err" | cut -c1-60)"
    return 1
  fi
  local changed added removed
  changed=$(diff -u "$base_out" "$head_out" 2>/dev/null | grep -cE '^[+-][^+-]' || true)
  added=$(diff  "$base_out" "$head_out" 2>/dev/null | grep -cE '^> ' || true)
  removed=$(diff "$base_out" "$head_out" 2>/dev/null | grep -cE '^< ' || true)
  local verdict="unchanged"
  [ "$changed" -gt 0 ] && verdict="changed"
  # Only call it new when the values file is actually new. A base that failed to
  # render is NO-BASE — an unusable comparison, not a finding.
  if [ "$base_rc" = "2" ]; then verdict="new"
  elif [ "$base_rc" = "1" ] || { [ ! -s "$base_out" ] && [ -s "$head_out" ]; }; then verdict="NO-BASE"; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$env_name" "$verdict" "$added" "$removed" "$(wc -l < "$head_out" | tr -d ' ')"
}
export -f render_one 2>/dev/null || true

RESULTS="$WORK/results.tsv"
: > "$RESULTS"
n=0
for vals in "$VALUES_DIR"/*.yaml; do
  [ -f "$vals" ] || continue
  env_name="$(basename "$vals" .yaml)"
  ( render_one "$env_name" "$vals" >> "$RESULTS" ) &
  n=$((n + 1))
  while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n 2>/dev/null || sleep 0.2; done
done
wait

# ------------------------------------------------------------------ report
printf '\nRender matrix — %s @ %s (%d environments)\n\n' "$NAME" "${BASE_SHA:0:8}" "$n"
printf '%-16s %-12s %7s %7s %8s\n' "environment" "verdict" "+lines" "-lines" "total"
printf '%s\n' "------------------------------------------------------------"
sort "$RESULTS" | while IFS=$'\t' read -r c v a r t; do
  printf '%-16s %-12s %7s %7s %8s\n' "$c" "$v" "$a" "$r" "$t"
done

FAILED=$(grep -c 'RENDER-FAIL' "$RESULTS" || true)
NOBASE=$(awk -F'\t' '$2=="NO-BASE"' "$RESULTS" | wc -l | tr -d ' ')
CHANGED=$(awk -F'\t' '$2=="changed"' "$RESULTS" | wc -l | tr -d ' ')
UNCH=$(awk -F'\t' '$2=="unchanged"' "$RESULTS" | wc -l | tr -d ' ')

printf '\n  %s changed · %s unchanged · %s no-base · %s failed\n' "$CHANGED" "$UNCH" "$NOBASE" "$FAILED"
if [ "$NOBASE" -gt 0 ]; then
  printf '  ** %s environment(s) could not render at the BASE commit, so their diff is meaningless.\n' "$NOBASE"
  printf '     Usually a subchart missing at base. Treat as UNVERIFIED, not as a change.\n'
fi

# "Everything unchanged" is only a finding if the branch touched the chart —
# otherwise it is the correct result, and warning on it trains you to skim past.
CHART_TOUCHED=$(git diff --name-only "$BASE_SHA"...HEAD -- "$CHART" 2>/dev/null | wc -l | tr -d ' ')
if [ "$CHART_TOUCHED" = "0" ]; then
  printf '  (no changes to %s on this branch — matrix is a baseline, not a diff)\n' "$CHART"
fi

# A values change that renders identically everywhere is inert — usually a wrong
# key path or a disabled component, not a no-op you intended.
if [ "$CHANGED" = "0" ] && [ "$FAILED" = "0" ] && [ "$CHART_TOUCHED" != "0" ]; then
  printf '  ** every environment rendered IDENTICAL — the change may be inert (wrong key path,\n'
  printf '     disabled component, or overridden downstream). Verify before claiming it works.\n'
fi
# Divergence across environments is the thing a single-environment render cannot see.
if [ "$CHANGED" -gt 0 ] && [ "$UNCH" -gt 0 ]; then
  printf '  ** change lands on %s environment(s) but NOT %s — confirm that asymmetry is intended.\n' "$CHANGED" "$UNCH"
fi

[ "$FAILED" -gt 0 ] && exit 1
exit 0
