# Hooks

Hooks are optional automation glue. They never replace the canonical protocols — canonical behavior lives in [`core/protocols/`](../protocols/). Hooks just make it harder to forget.

The end-to-end compaction lifecycle these hooks implement is documented in [`LIFECYCLE.md`](../../LIFECYCLE.md).

## Generic hooks (portable shell)

| Path | Purpose |
| --- | --- |
| [generic/pre-task-check.sh](generic/pre-task-check.sh) | Checks required tools, notes Graphify availability, runs `bd prime` when possible. |
| [generic/post-task-memory.sh](generic/post-task-memory.sh) | Wrapper for `bd remember` with sanitization guard. |
| [generic/rtk-wrapper.sh](generic/rtk-wrapper.sh) | Wraps documented `rtk-safe` commands with `rtk`. |
| [generic/learning-gate.py](generic/learning-gate.py) | Learning-capture gate; records usage telemetry — reads + citations (see below). |
| [generic/comment-discipline.sh](generic/comment-discipline.sh) | Blocking gate on code-comment discipline: banned refs, 2-line block ceiling, per-file density, 13-line ceiling on a Python function / function-body docstring. |
| [generic/test-discipline.sh](generic/test-discipline.sh) | Blocking gate on test VOLUME: added test LOC within `TEST_FIXED_LINES + MAX_TEST_RATIO x` added prod LOC (defaults `220` and `1.2`). |

> The knowledge-home scripts (`knowledge-search.sh`, `drift-check.sh`, `learn.sh`) live in [`agent-knowledge/scripts/`](../../agent-knowledge/scripts/), not here — they belong to the shared knowledge home, not the runtime event hooks.

## learning-gate.py — capture enforcement + measurement

[`generic/learning-gate.py`](generic/learning-gate.py) turns the soft "remember to persist learnings" convention into a machine-checked gate, and measures which learnings actually get read and cited so consolidation can rank files and detect coverage gaps (never prune by usage). Stdlib only; it reads a JSON event on stdin and parses the transcript at `transcript_path`. It targets Claude-Code-style JSONL transcripts and may need a small `parse_transcript` tweak per runtime (see the file header).

Two events (map to your runtime's equivalents):

| Event | Behavior |
| --- | --- |
| `SubagentStop` | **Hard gate.** If a sub-agent did substantive work (file edits, commits/PRs, or `tool_uses >= LEARN_TOOLUSE_MIN`) but persisted nothing (`bd remember` / `bd comments add` / `learn.sh` / a `learnings-*.md` or native-memory edit), it blocks the stop **once** with a reason telling the agent to persist now or state nothing was non-obvious. A `stop_hook_active`-style flag prevents blocking loops. |
| `UserPromptSubmit` | **Soft nudge.** For the long-lived main session: a debounced one-line reminder when work has outpaced persistence by `LEARN_MAIN_GAP`. Never blocks. |

Both paths record usage telemetry under `${HARNESS_METRICS:-~/.agent-knowledge/metrics}`: per-file **read** counts in `learning-reads.json` (the primary signal, incremented on every `learnings-*.md` Read) plus `learning-reads.jsonl`, and per-entry `[learnings-<file>.md#<N>]` **citation** counts in `learning-usage.json` plus `learning-citations.jsonl`. [`templates/commands/consolidate.md`](../../templates/commands/consolidate.md) reads these for **ranking and gap-detection only — never for pruning**. Per-transcript dedupe (a `/tmp` marker) prevents double-counting on transcript growth.

| Env var | Default | Effect |
| --- | --- | --- |
| `LEARN_GATE_DISABLE` | unset | `1` disables both gating and nudging (citation logging still runs). |
| `LEARN_METRICS_DISABLE` | unset | `1` disables read/citation logging (gating/nudging still runs). |
| `LEARN_TOOLUSE_MIN` | `8` | Tool-use count that counts as "substantive" for the hard gate. |
| `LEARN_MAIN_GAP` | `2` | Work-minus-persist gap that triggers the soft nudge. |
| `HARNESS_METRICS` | `~/.agent-knowledge/metrics` | Where usage telemetry (reads + citations) is written. |

## The two discipline gates

[`generic/comment-discipline.sh`](generic/comment-discipline.sh) and [`generic/test-discipline.sh`](generic/test-discipline.sh) share one interface — `--staged`, `--base <ref>`, a bare invocation (diff vs merge-base with `origin/main`), or a diff on stdin with `-`. Exit `0` clean, `1` findings, `2` usage error. Both are **blocking** before a push and both are re-run at review time.

They bound the two things a reviewer otherwise keeps writing by hand:

- **Prose volume.** The docstring rule matters as much as the `#` rules: without it an author moves an essay out of a comment block into a triple-quoted string and passes untouched. Module and class docstrings are exempt at any length — the target is a multi-paragraph *function* docstring, or narrative prose standing in a function body.
- **Test volume.** The allowance is affine (`FIXED + RATIO x prod`), not a plain ratio, because one test carries a fixed scaffolding cost that does not shrink with the change.

Both thresholds are env-tunable (`MAX_COMMENT_LINES`, `MAX_DOCSTRING_LINES`, `TEST_FIXED_LINES`, `MAX_TEST_RATIO`). Retune to the repo rather than waiving the gate — a count can be argued with only by changing the count. The standards they enforce are canonical in [`core/protocols/code-quality.md`](../protocols/code-quality.md).

**Prove a gate can fail before trusting it.** Feed each one a diff built to trip it and confirm it exits 1, then a clean control and confirm it exits 0. A threshold that has never fired has not been shown capable of firing.

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
