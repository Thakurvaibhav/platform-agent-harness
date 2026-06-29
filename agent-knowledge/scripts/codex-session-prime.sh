#!/usr/bin/env bash
# Codex SessionStart hook: surface the shared bd hive so the session starts primed.
#
# Wired via ~/.codex/hooks.json:
#   {"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"<this-script>"}]}]}}
#
# Harmless if Codex doesn't inject hook stdout as context — AGENTS.md also instructs
# the agent to run `bd prime` itself. This just warms it and makes it visible.
#
# Output must be valid JSON per Codex's SessionStart hook contract:
#   {"continue":true,"suppressOutput":false,"hookSpecificOutput":{...}}
# Plain text causes "invalid session start JSON output" errors.
tmp="$(mktemp -t codex-session-prime.XXXXXX)"
if bd prime --memories-only >"$tmp" 2>&1; then
  count="$(grep -E '^## Persistent Memories \([0-9]+\)' "$tmp" | head -n 1 | sed -E 's/^## Persistent Memories \(([0-9]+)\).*$/\1/')"
  if [[ -n "$count" ]]; then
    context="[codex-session-prime] bd prime ok: ${count} memories loaded"
  else
    context="[codex-session-prime] bd prime ok"
  fi
else
  rc=$?
  context="[codex-session-prime] bd prime failed rc=${rc}; run manually: bd prime --memories-only"
  {
    echo "$context"
    tail -n 5 "$tmp"
  } >&2
fi
rm -f "$tmp"
escaped_context="$(printf '%s' "$context" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])')"
printf '{"continue":true,"suppressOutput":false,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$escaped_context"
exit 0
