# Handoff Report Template

Use this exact format at the end of every non-trivial sub-agent run. Parseable by the orchestrator; readable by humans.

```markdown
## Summary
<1–3 sentences: what was done and the outcome>

## Changes
- <file/path/or/resource>: <what changed and why>
(omit this section entirely for explicit read-only / research / validation tasks)

## Verification
- <check name>: <pass | fail | skipped> — <evidence/command output/link>
- helm dep build && helm lint && helm template: pass — rendered clean
- yamlfmt --lint charts/<chart>/values.yaml: pass
- gh pr checks <num>: pass

## Artifacts
- bd task: <id> — <status>
- PR: <#num> — <url> (if applicable)
- Ticket: <KEY> — <url> (if applicable)

## Knowledge updates
- Prior art used: <list of `[learnings-<file>.md#<N>]` entries cited during this task, or "None.">
- bd memories: <list of `bd remember --key ...` entries written this task, or "None.">
- references/log.md: <"appended one line" | "not appended (trivial/read-only)">
- references/learnings-*.md: <"<file>#<item> updated" | "new item <file>#<n> added" | "not changed (reason: trivial|operational-state|uncertain|already-captured)">
- references/index.md: <"updated row for <path>" | "not changed">
- Conflicts flagged: <"CONFLICT: <new finding> vs learnings-<file>.md#<n>" | "None.">

## Open questions / follow-ups
- <items the caller must decide>
- <out-of-scope issues filed as new bd tasks>
- "None." if nothing
```

## Variants

### Blocked

If the task cannot be completed, replace `## Changes` with `## Blockers`:

```markdown
## Blockers
- <what is missing>
- <what was attempted>
- <what the caller needs to provide>
```

Do not open PRs in a blocked state.

### Read-only / research

Omit `## Changes`. Lead with findings.

```markdown
## Summary
<finding>

## Evidence
- <command>: <key output>
- <link>: <key fact>

## Recommendations
1. <action 1>
2. <action 2>

## Open questions / follow-ups
- <items or "None.">
```

## Rules

- Every `Verification` bullet is backed by a command or link. Never claim "verified" without evidence.
- Failures must still be reported. Do not silently retry or mask them.
- The `## Knowledge updates` section is **mandatory** for every non-trivial task. If you have nothing to add, write `None.` next to each row — never omit the section. This is the explicit gate that keeps the local knowledge base ([`references/`](../references/README.md)) alive.
- Conflicts with existing `learnings-*.md` entries must be flagged explicitly in the report:
  ```
  CONFLICT: <new finding> vs references/learnings-<file>.md#<item-number>
  ```
  Do NOT silently edit learnings files — the human decides.
- The post-task discipline is canonical in [`core/protocols/bd-and-memory.md`](../core/protocols/bd-and-memory.md) "Task Completion Checklist". The promotion path from `bd remember` to numbered `learnings-*.md` items is in [`references/README.md`](../references/README.md).
