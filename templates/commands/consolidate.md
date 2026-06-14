# `/consolidate` — Knowledge Consolidation

Promotes durable insights from `bd memories` into the appropriate `agent-knowledge/references/learnings-*.md` files.

> **Note:** Most reusable insights should already be in learnings files via immediate ingest (see "Knowledge Ingest" in `core/protocols/bd-and-memory.md`). Consolidation catches stragglers, enforces cross-link lint, and cleans stale memories.

## When to run

- On session start if `<repo>/meta/last-consolidation` memory is missing or older than 7 days.
- After completing a large project with many `bd remember` calls.
- When `bd memories` count exceeds ~50 and keyword searches become noisy.

## Workflow

```bash
# 1. List all memories
bd memories

# 2. For each memory with prefix <repo>/decision, <repo>/lesson, <repo>/trouble, <repo>/tool:
#    - Find the matching learnings file using the Keywords column in agent-knowledge/references/index.md
#    - Check if the insight already exists (avoid duplicates)
#    - If not present and the insight is reusable, append as a numbered item
#    - Include (ref: #NNN) provenance when the memory references a PR or URL

# 3. New-file threshold: if 3+ memories share a domain keyword not served by any
#    existing learnings file, create learnings-<topic>.md and register in index.md

# 4. If a memory doesn't match any existing learnings file domain and doesn't meet
#    the 3+ threshold, skip it (stays as bd memory)

# 5. Cross-link lint: for each learnings file, verify its See also: header matches
#    the Cross-refs column in index.md. For entries mentioning keywords from another
#    file's domain, add missing See also: pointers. Fix broken references.

# 6. Usage-based pruning (citation heatmap):
#    Read agent-knowledge/metrics/learning-usage.json — per-entry citation counts
#    keyed learnings-<file>.md#<N>, written by core/hooks/generic/learning-gate.py.
#    - Entries NEVER cited (absent from learning-usage.json) AND older than 30 days:
#      ARCHIVE (do NOT delete) — move the entry into agent-knowledge/references/_archive/<file>
#      and list each archived entry in the handoff for human veto.
#    - Do NOT touch entries younger than 30 days, regardless of citation count.
#    - Stamp the highest-cited surviving entries with "(validated: <today's date>)".
#    - Report the top-5 most-cited entries + the count of archived entries.

# 7. Prune session memories:
#    bd forget memories whose key matches "session/*" or "*/pre-compact" that are
#    older than 7 days. Keep all other memories per the retain rule below.

# 8. Update agent-knowledge/references/index.md if any new learnings files were created

# 9. Record the consolidation
bd remember "last consolidation: <today's date>, promoted N memories to learnings files" \
  --key <repo>/meta/last-consolidation
```

## Rules

- **Do NOT auto-run.** Always ask the user first.
- **Default: retain memories after promoting** (audit trail). Advanced adopters with established ingest discipline may `bd forget` promoted memories to reduce search noise.
- **One insight per numbered entry.** Keep entries self-contained with file paths or commands where applicable.
- **Include provenance** — carry `(ref: #NNN)` or `(ref: <url>)` from the memory text into the learnings entry when applicable.
- **Skip operational state memories** (deployment status, cluster health snapshots) — they are not reusable learnings.
- **Match existing tone and granularity** in the target learnings file.
- **Archive, never delete, learnings entries.** Usage-based pruning (step 6) moves uncited, >30-day-old entries to `agent-knowledge/references/_archive/` and lists them for human veto — it does not remove them. Only `session/*` and `*/pre-compact` bd memories (step 7) are deleted, and only past 7 days.
