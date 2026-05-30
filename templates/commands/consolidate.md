# `/consolidate` — Knowledge Consolidation

Promotes durable insights from `bd memories` into the appropriate `references/learnings-*.md` files.

## When to run

- On session start if `<repo>/meta/last-consolidation` memory is missing or older than 7 days.
- After completing a large project with many `bd remember` calls.
- When `bd memories` count exceeds ~50 and keyword searches become noisy.

## Workflow

```bash
# 1. List all memories
bd memories

# 2. For each memory with prefix <repo>/decision, <repo>/lesson, <repo>/trouble, <repo>/tool:
#    - Find the matching learnings file using the Keywords column in references/index.md
#    - Check if the insight already exists (avoid duplicates)
#    - If not present and the insight is reusable, append as a numbered item

# 3. If a memory doesn't match any existing learnings file domain, skip it (stays as bd memory)

# 4. Update references/index.md if any new learnings files were created

# 5. Record the consolidation
bd remember "last consolidation: <today's date>, promoted N memories to learnings files" \
  --key <repo>/meta/last-consolidation
```

## Rules

- **Do NOT auto-run.** Always ask the user first.
- **Do NOT delete memories after promoting.** Memories serve as the audit trail; learnings files serve as the curated reference.
- **One insight per numbered entry.** Keep entries self-contained with file paths or commands where applicable.
- **Skip operational state memories** (deployment status, cluster health snapshots) — they are not reusable learnings.
- **Match existing tone and granularity** in the target learnings file.
