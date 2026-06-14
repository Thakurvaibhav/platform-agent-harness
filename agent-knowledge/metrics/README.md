# `agent-knowledge/metrics/` — citation heatmap

Usage telemetry for the curated knowledge base. The learning-gate hook
([`core/hooks/generic/learning-gate.py`](../../core/hooks/generic/learning-gate.py))
writes these files as agents cite learnings; consolidation reads them to prune
by **actual usage** instead of guesswork.

## Files

| File | Shape | Role |
| --- | --- | --- |
| `learning-usage.json` | `{"learnings-<file>.md#<N>": <count>, ...}` | Per-entry citation counts. The heatmap. |
| `learning-citations.jsonl` | one JSON object per line: `{"cite": "learnings-<file>.md#<N>", "source": "main\|subagent", "transcript": "<id>"}` | Append-only citation log (audit trail behind the counts). |

A "citation" is any `[learnings-<file>.md#<N>]` reference an agent emits in its
output. The hook dedupes per transcript so re-reads of the same transcript do
not double-count.

## How consolidation uses it

`/consolidate` (see [`templates/commands/consolidate.md`](../../templates/commands/consolidate.md)):

- Entries **never cited** and **older than 30 days** are archived to
  `agent-knowledge/references/_archive/` (archived, not deleted) and listed in
  the handoff for human veto.
- The **highest-cited survivors** get stamped `(validated: <date>)`.
- Entries younger than 30 days are left untouched regardless of citations.

## Not committed

The metrics files are runtime-generated and machine-local — they are **not**
committed. Only this `README.md` and a `.gitkeep` live in version control. The
deployed home writes its metrics to `${HARNESS_METRICS:-~/.agent-knowledge/metrics}`.
