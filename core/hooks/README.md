# Hooks

Hooks are optional automation glue. They never replace the canonical protocols — canonical behavior lives in [`core/protocols/`](../protocols/). Hooks just make it harder to forget.

The end-to-end compaction lifecycle these hooks implement is documented in [`LIFECYCLE.md`](../../LIFECYCLE.md).

## Generic hooks (portable shell)

| Path | Purpose |
| --- | --- |
| [generic/pre-task-check.sh](generic/pre-task-check.sh) | Checks required tools, notes Graphify availability, runs `bd prime` when possible. |
| [generic/post-task-memory.sh](generic/post-task-memory.sh) | Wrapper for `bd remember` with sanitization guard. |
| [generic/rtk-wrapper.sh](generic/rtk-wrapper.sh) | Wraps documented `rtk-safe` commands with `rtk`. |
| [generic/learning-gate.py](generic/learning-gate.py) | Learning-capture gate; records the citation heatmap (see below). |

> The knowledge-home scripts (`knowledge-search.sh`, `drift-check.sh`, `learn.sh`) live in [`agent-knowledge/scripts/`](../../agent-knowledge/scripts/), not here — they belong to the shared knowledge home, not the runtime event hooks.

## learning-gate.py — capture enforcement + measurement

[`generic/learning-gate.py`](generic/learning-gate.py) turns the soft "remember to persist learnings" convention into a machine-checked gate, and measures which learnings actually get cited so consolidation can prune by usage. Stdlib only; it reads a JSON event on stdin and parses the transcript at `transcript_path`. It targets Claude-Code-style JSONL transcripts and may need a small `parse_transcript` tweak per runtime (see the file header).

Two events (map to your runtime's equivalents):

| Event | Behavior |
| --- | --- |
| `SubagentStop` | **Hard gate.** If a sub-agent did substantive work (file edits, commits/PRs, or `tool_uses >= LEARN_TOOLUSE_MIN`) but persisted nothing (`bd remember` / `bd comments add` / `learn.sh` / a `learnings-*.md` or native-memory edit), it blocks the stop **once** with a reason telling the agent to persist now or state nothing was non-obvious. A `stop_hook_active`-style flag prevents blocking loops. |
| `UserPromptSubmit` | **Soft nudge.** For the long-lived main session: a debounced one-line reminder when work has outpaced persistence by `LEARN_MAIN_GAP`. Never blocks. |

Both paths log new `[learnings-<file>.md#<N>]` citations to `learning-citations.jsonl` and increment per-entry counts in `learning-usage.json` under `${HARNESS_METRICS:-~/.agent-knowledge/metrics}` — the citation heatmap that [`templates/commands/consolidate.md`](../../templates/commands/consolidate.md) reads for usage-based pruning. Per-transcript dedupe (a `/tmp` marker) prevents double-counting on transcript growth.

| Env var | Default | Effect |
| --- | --- | --- |
| `LEARN_GATE_DISABLE` | unset | `1` disables both gating and nudging (citation logging still runs). |
| `LEARN_METRICS_DISABLE` | unset | `1` disables citation logging (gating/nudging still runs). |
| `LEARN_TOOLUSE_MIN` | `8` | Tool-use count that counts as "substantive" for the hard gate. |
| `LEARN_MAIN_GAP` | `2` | Work-minus-persist gap that triggers the soft nudge. |
| `HARNESS_METRICS` | `~/.agent-knowledge/metrics` | Where the citation heatmap is written. |

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
