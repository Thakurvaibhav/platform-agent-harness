# Parallel Dispatch Protocol

When the same operation needs to run across N independent targets — clusters, services, components, regions, dashboards, charts — dispatch N specialist or worker sub-agents in parallel rather than serially.

## When to parallelize

Parallelize when **all** of these are true:

- The targets are independent: no shared state, no ordering requirement.
- Each target uses the same playbook with target-specific parameters.
- Results can be aggregated afterwards by the orchestrator.

Examples that fit:

- Validating a configuration across N clusters.
- Auditing N services for the same readiness criteria.
- Generating N dashboards from the same template.
- Building N Helm charts that share a wrapper pattern.
- Reviewing N PRs against the same checklist.

Examples that do **not** fit:

- A → B → C dependency chains.
- Operations against shared global state (a single chart, a single PR).
- Anything that mutates the same file path concurrently.

## Dispatch shape

In the orchestrator (often `task-planner` or the main session):

1. Pick a single, sanitized playbook (numbered checks, exact commands, pass/fail criteria, evidence).
2. Build per-target parameter sets — keep them small.
3. Launch all worker dispatches **in one message** so the runtime can fan them out.
4. Wait for every worker to return before aggregating.
5. Produce a single consolidated handoff report keyed by target.

## Worker prompt template

```markdown
Goal: <one sentence>
Target: <cluster | service | dashboard | chart>
Parameters: <target-specific values>
Playbook: <link to a numbered checklist with commands and expected evidence>
Constraints:
- Read-only unless explicitly told otherwise.
- No mutating Kubernetes / Helm / git operations.
- Sanitize before returning (no real identifiers, tokens, URLs).
Verify by:
- <check 1>: <pass/fail criterion>
- <check 2>: <pass/fail criterion>
Return: structured handoff (see core/protocols/safety-and-handoff.md).
Before finishing, persist any non-obvious finding:
bd remember "<insight>" --key <repo>/<prefix>/<topic>
```

## Aggregation in the orchestrator

After all workers return:

1. Diff per-target results against the playbook's pass/fail criteria.
2. Surface only what differs — a green matrix is enough for the rest.
3. Flag any worker that timed out or returned a `Blockers` section instead of `Changes`.
4. File follow-up `bd` tasks for each failed target before closing the parent task.

## Why this matters

A well-structured playbook plus parallel workers turns hours of sequential investigation into minutes of fan-out and a clean diff. Empirical observation: a 12-check mTLS readiness playbook run across 3 clusters in parallel completes in ~5 minutes vs ~45 minutes sequential — **3x+ wall-clock speedup**. Creation cost (~1 hour) was amortized across every subsequent run.

Two heuristics:

- If you find yourself doing the same investigation more than twice, write the playbook.
- If a playbook needs to run across more than two independent targets, fan it out.

## Validation playbooks are the highest-ROI artifact

A well-structured playbook (numbered checks, pass/fail criteria, specific commands/queries per check) can be executed by any agent instance with no additional context. The playbook is the unit of leverage; parallel dispatch is how you apply it at scale.
