# Codex Global Instructions (Overlay)

**Single source of truth:** Read `~/.agent-knowledge/references/shared-protocols-core.md`
(or your equivalent shared core) at the start of every session -- it holds the
shared, harness-neutral protocols (identity, startup, bd hive, prior-art search,
knowledge capture, delegation philosophy). For engineering work also read
[`core/protocols/code-quality.md`](../core/protocols/code-quality.md) — the canonical
coding standards (assumptions, simplicity, reuse-first, surgical changes, comments,
verification, reflexes) that Claude, Codex, and Factory all follow. This overlay adds
ONLY Codex-specific mechanics.

## Memory: bd hive is canonical -- ignore native Codex memory

The bd hive at `$BEADS_DB` (a running Dolt daemon) is the one brain shared with
other runtimes (Claude Code, Factory, etc.). Run `bd prime --memories-only` at
start; persist with `bd remember "<insight>" --key <domain>/<category>/<topic>`.
Codex's own SQLite memory/goals are local and invisible to other agents -- do NOT
use them for durable or cross-runtime knowledge.

## Sandbox

For full bd hive access, this install runs `sandbox_mode = "danger-full-access"`
so workers can reach the Dolt daemon (127.0.0.1:50656) and write the canonical
hive. Act with corresponding care on destructive commands.

If using the default `workspace-write` sandbox instead, add the `.beads` directory
to writable roots and enable localhost TCP for the Dolt connection.

## Token optimization (manual -- no auto-hook on Codex)

`rtk` has no Codex hook processor, so it is NOT auto-applied. Manually prefix
verbose read-only commands: `rtk git status`, `rtk git diff`, `rtk helm template`,
`rtk kubectl get`, `rtk gh pr view`. Never prefix mutating or piped commands.

## Subagents / fan-out (parity via `codex exec`)

Codex has no native subagent type. To delegate or fan out, spawn headless workers:
`codex exec "<task>"` (add `--cd <dir>` to target a repo). Each worker inherits
this AGENTS.md, the MCP servers, and the bd hive. Dispatch pattern:

- Give each worker a self-contained prompt: goal, references, constraints,
  "Verify by:" criteria, and the standard preamble (run `bd prime --memories-only`,
  search prior art, cite learnings, persist findings).
- For parallel work, launch multiple `codex exec` workers on DISTINCT bd tasks to
  avoid write races on the shared hive.
- Specialist worker prompts live in `agent-knowledge/scripts/codex-dispatch.sh`
  which loads role definitions from `core/agents/<name>.md`.

## Hooks

Configure in `~/.codex/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "<path-to>/agent-knowledge/scripts/codex-session-prime.sh"
          }
        ]
      }
    ]
  }
}
```

The SessionStart hook warms the bd hive and reports the memory count. Codex hooks
must emit valid JSON to stdout (the `hookSpecificOutput` contract); plain text
causes "invalid session start JSON output" errors.

## Cross-runtime review

Use `codex review` (or `codex exec review`) to review a branch/diff -- including
work produced by other runtimes. Write findings to the bd hive so other agents
see them.
