# `agent-knowledge/metrics/` — usage telemetry

Usage telemetry for the curated knowledge base. The learning-gate hook
([`core/hooks/generic/learning-gate.py`](../../core/hooks/generic/learning-gate.py))
writes these files as agents read and cite learnings; consolidation reads them
to **rank** files and **detect coverage gaps** — never to prune.

Two signals, read-frequency primary:

## Files

| File | Shape | Role |
| --- | --- | --- |
| `learning-reads.json` | `{"learnings-<file>.md": <count>, ...}` | **Primary signal.** Per-file read counts, incremented whenever a `learnings-*.md` file is Read. Agents read learnings constantly but cite `#N` rarely, so reads are the truer usage proxy. |
| `learning-reads.jsonl` | one JSON object per line: `{"file": "learnings-<file>.md", "source": "main\|subagent", "transcript": "<id>"}` | Append-only read log (audit trail behind the counts). |
| `learning-usage.json` | `{"learnings-<file>.md#<N>": <count>, ...}` | Secondary signal. Per-entry citation counts. |
| `learning-citations.jsonl` | one JSON object per line: `{"cite": "learnings-<file>.md#<N>", "source": "main\|subagent", "transcript": "<id>"}` | Append-only citation log. |

A "citation" is any `[learnings-<file>.md#<N>]` reference an agent emits in its
output. The hook dedupes per transcript so re-reads of the same transcript do
not double-count.

## How consolidation uses it

`/consolidate` (see [`templates/commands/consolidate.md`](../../templates/commands/consolidate.md)) uses these signals for **ranking and gap-detection ONLY — never pruning**:

- **NEVER archive or delete a learning for low/zero reads.** Read frequency != value; recall >> precision in this domain (a rarely-read entry may hold a once-a-year gotcha that prevents an incident).
- **Rank, not cull:** report the most-read learnings files; optionally stamp the hottest file's key entries with `(validated: <date>)`.
- **Gap-detection (higher-value use):** cross-reference reads against where work is actually happening (recent bd memories/PRs by domain). Active work + a rarely-read learnings file = a discoverability or coverage gap to flag, never auto-remove.
- Learnings are removed only when **incorrect or superseded**, never by usage.

## Not committed

The metrics files are runtime-generated and machine-local — they are **not**
committed. Only this `README.md` and a `.gitkeep` live in version control. The
deployed home writes its metrics to `${HARNESS_METRICS:-~/.agent-knowledge/metrics}`.
