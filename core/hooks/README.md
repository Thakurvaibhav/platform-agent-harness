# Hooks

Hooks are optional automation glue. They never replace the canonical protocols — canonical behavior lives in [`core/protocols/`](../protocols/). Hooks just make it harder to forget.

The end-to-end compaction lifecycle these hooks implement is documented in [`LIFECYCLE.md`](../../LIFECYCLE.md).

## Generic hooks (portable shell)

| Path | Purpose |
| --- | --- |
| [generic/pre-task-check.sh](generic/pre-task-check.sh) | Checks required tools, notes Graphify availability, runs `bd prime` when possible. |
| [generic/post-task-memory.sh](generic/post-task-memory.sh) | Wrapper for `bd remember` with sanitization guard. |
| [generic/rtk-wrapper.sh](generic/rtk-wrapper.sh) | Wraps documented `rtk-safe` commands with `rtk`. |

## Adapter hooks (Factory Droid examples)

These run in the Factory Droid runtime but the patterns translate directly to other runtimes that expose comparable hook events.

| Path | Event | Purpose |
| --- | --- | --- |
| [factory-droid/rtk-autoprefix.py](factory-droid/rtk-autoprefix.py) | PreToolUse | Auto-inserts `rtk` for allowlisted commands; preserves `sudo` / `env=` / `time` wrappers. |
| [factory-droid/ctx-threshold-warn.py](factory-droid/ctx-threshold-warn.py) | UserPromptSubmit | Uses [`core/statusline/statusline-context.py`](../statusline/statusline-context.py) to compute actual utilization and nudges `/compact` past `CTX_COMPACT_THRESHOLD` (default 85%). |
| [factory-droid/pre-compact-bd-sync.py](factory-droid/pre-compact-bd-sync.py) | PreCompact | Parses transcript, extracts PR / bd / ticket refs, writes `session/pre-compact` memory, adds snapshot comment to every in-progress bd task. |
| [factory-droid/post-compact-prime-reminder.sh](factory-droid/post-compact-prime-reminder.sh) | SessionStart | Reloads bd context with `bd prime` after compaction. |

## Companion helper

[`core/statusline/statusline-context.py`](../statusline/statusline-context.py) is a generic JSONL transcript parser returning `{pct, tokens, ctx_max, model, cpt}`. Both the statusline and the threshold-warn hook import it.

## Adoption rules

- Keep hooks small and auditable.
- Keep secrets out of hook files.
- Runtime-specific config belongs in adapters or local settings, not public root docs.
- Hooks should call the same protocols documented elsewhere instead of inventing separate behavior.
