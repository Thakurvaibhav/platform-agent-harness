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

# 6. Usage signal — READ-FREQUENCY, for ranking and gap-detection ONLY (NEVER pruning):
#    Read agent-knowledge/metrics/learning-reads.json (per-file read counts,
#    written by the learning-gate hook on every learnings-*.md Read +
#    knowledge-search.sh consult). This REPLACES citation counts as primary
#    usage signal — reads are a truer proxy (agents read learnings constantly
#    but rarely type explicit #N citations).
#    - NEVER archive or delete a learning for low/zero reads.
#      Read frequency != value — a rarely-read file may hold a once-a-year
#      gotcha that prevents a production incident.
#    - RANK, not cull: report the most-read learnings files; optionally stamp
#      the hottest file's key entries with "(validated: <today's date>)".
#    - GAP-DETECTION (higher-value use): cross-reference reads against where
#      work is happening (recent bd memories/PRs by domain). A domain with
#      active work but a rarely/never-read learnings file signals a
#      discoverability or coverage gap — flag it, never auto-remove.
#    - Report top 5 most-read files and any flagged gaps.
#    - Learnings are removed ONLY when incorrect or superseded (step 5).

# 7. Keep the hive lean by PROMOTION, not deletion:
#    Aggressively promote reusable bd memories into learnings-*.md (step 2b)
#    so durable knowledge lives in the searchable learnings layer and bd holds
#    only active/high-signal memories. Separately, "session/pre-compact-*"
#    (session-scoped checkpoints), legacy "*/pre-compact", and "session/adhoc"
#    memories older than 7 days are short-term continuity only — bd forget those.
#    Goal: a small, high-signal persistent-memory set so priming stays cheap.

# 8. Prune session memories:
#    bd forget memories whose key matches "session/*" or "*/pre-compact" that are
#    older than 7 days. Keep all other memories per the retain rule below.

# 9. New-file threshold: if 3+ memories share a domain keyword not covered by any
#    existing learnings file, create a new learnings-<topic>.md with those entries
#    and add it to index.md.

# 10. Update agent-knowledge/references/index.md if any new learnings files were created

# 11. Record the consolidation
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
- **NEVER prune learnings by usage.** Read-frequency (step 6) is for ranking and gap-detection only, NOT pruning. Rarely-read entries may hold critical once-a-year gotchas. Learnings are removed only when incorrect/superseded (step 5). Only `session/*` and `*/pre-compact` bd memories (step 8) are deleted, and only past 7 days.
