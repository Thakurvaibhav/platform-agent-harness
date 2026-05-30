# Dispatch Prompt Template

Use this exact shape when delegating to a specialist sub-agent or `general-engineer`.

```markdown
## Goal
<one sentence: what you want done>

## Target architecture / outcome
<one paragraph stating the intended end state, BEFORE any "explore the repo" instructions>

## Context
- bd task: <id>
- External ticket: <KEY> — <URL>
- Why it matters: <one line>

## Steps
1. cd <repo-root> && bd update <id> --claim
2. <specific step>
3. <specific step>

## Reference
- <files to read first>
- <patterns to follow>
- <related learnings: references/learnings-<file>.md item <#>>

## Constraints
- <what to preserve / not touch>
- <scope: which clusters, environments, files>

## Verify by
- <command/check>: <pass/fail criterion>
- <command/check>: <pass/fail criterion>
- <command/check>: <pass/fail criterion>

## Expected output
- PR: <title>
- Files: <expected diff scope>
- Handoff format: see core/protocols/safety-and-handoff.md

## Memory
Before finishing:
bd remember "<self-contained insight>" --key <repo>/<prefix>/<topic>
```

## Why each section matters

- **Goal** — single sentence so the agent can repeat back its understanding.
- **Target architecture FIRST** — sub-agents bias toward current repo state; buried targets get ignored.
- **bd task ID + ticket** — claim discipline and traceability.
- **Verify by** — the most important section. Vague verification produces vague results.
- **Memory** — every non-trivial dispatch teaches the harness something.

## For parallel dispatch

When fanning out to N targets, see [`core/protocols/parallel-dispatch.md`](../core/protocols/parallel-dispatch.md) and use the parallel-dispatch variant there.
