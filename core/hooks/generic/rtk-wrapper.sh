#!/usr/bin/env bash
# Generic wrapper that prefixes documented rtk-safe commands with `rtk`.
#
# Use this for runtimes that do not expose a PreToolUse hook but do let you
# wrap shell invocations. Bails out cleanly when `rtk` is not installed or
# when the command involves shell chaining / substitution.

set -u

cmd=("$@")
if [ ${#cmd[@]} -eq 0 ]; then
  exit 0
fi

joined="$*"
case "$joined" in
  *"|"*|*"&&"*|*"||"*|*";"*|*"\$("*|*'`'*|*"<("*|*">("*)
    exec "${cmd[@]}"
    ;;
esac

if ! command -v rtk >/dev/null 2>&1; then
  exec "${cmd[@]}"
fi

# Caller's escape hatch for when the raw output IS the evidence.
if [ "${RTK_DISABLE:-0}" != "0" ]; then
  exec "${cmd[@]}"
fi

# `gh pr diff` must never be compressed: rtk drops whole files from it. The subcommand
# may follow flags (`gh pr -R o/r diff`), and over-matching only costs compression.
if [ "${cmd[0]}" = "gh" ] && [ "${cmd[1]:-}" = "pr" ]; then
  _i=2
  while [ "$_i" -lt "${#cmd[@]}" ]; do
    if [ "${cmd[$_i]}" = "diff" ]; then exec "${cmd[@]}"; fi
    _i=$((_i + 1))
  done
fi

# Allowlist matches the canonical list in core/protocols/rtk-command-policy.md.
case "${cmd[0]} ${cmd[1]:-}" in
  "git status"|"git diff"|"git log"|"git show"|"git branch"|\
  "gh pr"|"gh issue"|"gh run"|\
  "docker ps"|"docker logs"|\
  "kubectl get"|"kubectl describe"|"kubectl logs"|"kubectl top"|\
  "helm template"|"helm lint"|"helm dependency"|"helm show"|\
  "cargo test"|"cargo build"|"npm test"|"pnpm test"|"pytest "|"go test"|"go build"|"tsc "|\
  "terraform plan"|\
  "gcx --agent")
    exec rtk "${cmd[@]}"
    ;;
esac

exec "${cmd[@]}"
