# Hook Installation

Hooks are runtime-specific. Use [`core/hooks/generic/`](../core/hooks/generic/) for portable shell examples and runtime adapter folders for platform-specific wiring. The hook catalog is [`core/hooks/README.md`](../core/hooks/README.md).

The end-to-end compaction lifecycle these hooks implement is in [`LIFECYCLE.md`](../LIFECYCLE.md).

The protocols and topic learnings hooks read live in the shared knowledge home [`agent-knowledge/`](../agent-knowledge/) (its `references/` and `scripts/`); the home's location is overridable via `HARNESS_REFS` / `HARNESS_METRICS`. See [`agent-knowledge/README.md`](../agent-knowledge/README.md).

## Recommended hook points

| Hook point | Purpose | Canonical protocol |
| --- | --- | --- |
| Session start | Run `bd prime` and load durable task / memory context. | [`core/protocols/bd-and-memory.md`](../core/protocols/bd-and-memory.md) |
| Pre-tool use | Apply `native-tool` / `rtk-safe` / `raw-required` command policy. | [`core/protocols/rtk-command-policy.md`](../core/protocols/rtk-command-policy.md) |
| Pre-compaction | Snapshot transcript into bd memory and per-task comments. | [`LIFECYCLE.md`](../LIFECYCLE.md) |
| User-prompt-submit | Warn when context utilization passes `CTX_COMPACT_THRESHOLD`. | [`LIFECYCLE.md`](../LIFECYCLE.md) |
| Subagent-stop + user-prompt-submit | Enforce + measure learning capture (`learning-gate.py`). | [`core/hooks/README.md`](../core/hooks/README.md) |
| Post-task | Store durable learnings with `bd remember`. | [`core/protocols/bd-and-memory.md`](../core/protocols/bd-and-memory.md) |
| Pre-push / PR creation | Run the blocking discipline gates (`comment-discipline.sh`, `test-discipline.sh`). | [`core/protocols/code-quality.md`](../core/protocols/code-quality.md) |
| Pre-publish | Run redaction and secret scans. | [`sanitization/prepublish-checklist.md`](../sanitization/prepublish-checklist.md) |

Do not commit runtime settings containing credentials or local paths.

## Learning-capture gate (`learning-gate.py`)

[`core/hooks/generic/learning-gate.py`](../core/hooks/generic/learning-gate.py) binds to two events:

- **`SubagentStop`** — hard gate: blocks a sub-agent's stop **once** if it did substantive work (file edits, commits/PRs, or `tool_uses >= LEARN_TOOLUSE_MIN`) but persisted nothing (`bd remember` / `learn.sh` / a `learnings-*.md` or native-memory edit).
- **`UserPromptSubmit`** — soft, debounced nudge for the long-lived main session when work outpaces persistence by `LEARN_MAIN_GAP`.

Both paths record usage telemetry under `${HARNESS_METRICS:-~/.agent-knowledge/metrics}`: per-file read counts (`learning-reads.json`/`.jsonl`, the primary signal) and per-entry `[learnings-<file>.md#<N>]` citation counts (`learning-usage.json`/`learning-citations.jsonl`). Consolidation uses these for ranking and gap-detection only — never for pruning. Env switches: `LEARN_GATE_DISABLE`, `LEARN_METRICS_DISABLE`, `LEARN_TOOLUSE_MIN` (default 8), `LEARN_MAIN_GAP` (default 2), `HARNESS_METRICS`. Map the two event names to your runtime's equivalents; the transcript parser targets Claude-Code-style JSONL and may need a small per-runtime tweak (see the hook's file header).

## Discipline gates (`comment-discipline.sh`, `test-discipline.sh`)

Two blocking gates run before every push and again at review. They are plain scripts, not runtime hooks, so they wire the same way into any runtime — a pre-push git hook, a CI step, or a step in the PR-creation flow:

```bash
core/hooks/generic/comment-discipline.sh --base origin/main || exit 1
core/hooks/generic/test-discipline.sh    --base origin/main || exit 1
```

Both accept `--staged` (pre-commit), `--base <ref>`, or a diff on stdin with `-`. Exit `0` clean, `1` findings, `2` usage error. Thresholds are env-tunable — `MAX_COMMENT_LINES` (2), `MAX_DOCSTRING_LINES` (13), `TEST_FIXED_LINES` (220), `MAX_TEST_RATIO` (1.2). Retune them to the repo instead of skipping the gate; the whole point is a number that cannot be argued with. Catalog and rationale: [`core/hooks/README.md`](../core/hooks/README.md).

## Adoption checklist

1. Install required tools from [`prerequisites.md`](prerequisites.md).
2. Choose a runtime adapter from [`../adapters/`](../adapters/).
3. Wire only the hooks supported by that runtime.
4. Keep hook scripts generic and public-safe.
5. Keep local runtime config uncommitted.
