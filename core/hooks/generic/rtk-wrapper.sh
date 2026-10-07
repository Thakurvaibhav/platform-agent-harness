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

# `gh pr diff` must never be compressed: rtk drops whole files from it, and a
# reviewer working off the truncated diff never learns what it skipped. Checked
# before the allowlist, whose two-token `gh pr` arm would otherwise swallow it.
case "${cmd[0]} ${cmd[1]:-} ${cmd[2]:-}" in
  "gh pr diff")
    exec "${cmd[@]}"
    ;;
esac

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
