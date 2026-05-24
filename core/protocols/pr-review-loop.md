# PR Review Loop

A second-agent pass on infrastructure PRs catches drift between intent and diff before a human looks at it.

## Dispatch matrix

The orchestrator (or the agent that opened the PR) decides whether to dispatch [`core/agents/pr-reviewer.md`](../agents/pr-reviewer.md).

### Always dispatch

- Helm chart changes (any chart-author sub-agent or human).
- ArgoCD application or values changes.
- CI / alerting / SLO / observability changes.
- Any PR touching more than ~5 files or ~100 lines.
- Any PR touching security-sensitive paths: secrets, RBAC, NetworkPolicies, escalation policies, image policies, admission controllers.

### Never dispatch

- Docs-only changes (README, CHANGELOG, comments).
- Single-value config changes under ~10 lines.
- User explicitly says "trivial", "skip review", or "no review".

### Use judgment

- 3–5 files, 50–100 lines: dispatch if logic changes, skip if pure scaffolding.
- Worker-sub-agent PRs: dispatch when the original task was non-trivial.
- Cross-cutting refactors: dispatch regardless of size.

## Dispatch prompt template

```markdown
Goal: Review and fix PR <url>
Context: <one-line summary of the original task>
Key files: <paths most relevant to the change>
Constraints: <what to preserve / not touch>
Protocol: Review diff, fix blocking issues, check CI, iterate at most 2 times, then hand off to human.
Verify by:
- <check 1>: <pass/fail criterion>
- <check 2>: <pass/fail criterion>
Before finishing, persist any non-obvious finding:
bd remember "<insight>" --key <repo>/<prefix>/<topic>
```

Specify a different model from the creating sub-agent when the runtime supports it — a fresh perspective catches more issues.

## Known-bot handling

Public PR-comment bots (e.g. `cursor[bot]`, `coderabbitai[bot]`) post findings several minutes after a PR opens. The reviewer should:

1. Identify expected bots from the repo's review config.
2. Wait up to a budgeted window (e.g. 10 minutes total, polling in parallel) for each bot to post a review, top-level comment, or inline comment.
3. Read all bot findings into the review context before doing its own pass.
4. Reply once per bot finding using the categories below, citing fix commits or specific technical evidence.

| Category | When to use |
| --- | --- |
| Fixed | A commit in this loop fixes it — cite the SHA. |
| Acknowledged | Valid finding but non-blocking — say why it is deferred. |
| Disagree | False positive or misread context — cite specific evidence. |
| Out of scope | Valid but belongs in a separate task — link the bd task. |

Never silently ignore a bot finding. If you have nothing to say, choose `Disagree` with a one-line reason or `Acknowledged` if it is noise.

## Iteration cap

**Two fix iterations is the hard cap.** After two, document the unresolved item and hand off.

## Review checklist

1. Correctness
2. Security and secret exposure
3. Reuse and duplication (search `utils/`, `helpers/`, `common/`, `shared/`, `lib/` first)
4. Repo conventions and style
5. Edge cases (nil, empty, boundary, timeout)
6. Completeness against the original task summary
7. Validation and CI status

## Reviewer output

```markdown
## PR Review Summary

### What was reviewed
- <areas>

### Bot reviews ingested
- <bot>: <posted N findings | timed out | not present>

### Direct replies posted to bots
- <bot>: <fixed M | acknowledged K | disagreed L | out-of-scope J>

### Blocking issues fixed
- <issue> — fixed in <sha>

### Non-blocking observations
- <items or "None.">

### Unresolved items
- <items or "None.">

### CI status
- <pass / fail / pending / no checks>

### Status
Ready for human review / Has unresolved items
```
