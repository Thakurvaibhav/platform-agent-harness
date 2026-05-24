---
name: contract-validation
description: >-
  Validate a feature, workflow, or platform change against an explicit
  contract. Generic — does not require a dedicated validator agent. Any CLI
  agent executes the contract, collects evidence, and produces a structured
  report.
---

# Contract Validation

Use when a feature, rollout, or platform change needs to be validated against an explicit pass/fail contract.

## Inputs

- **Validation contract** — a list of numbered assertions, each with a pass/fail criterion and required evidence.
- **Target** — repo, service, cluster, dashboard.
- **Preconditions** — what must be true before starting.
- **Test surface** — docs, CLI, API, UI, Kubernetes, GitOps, observability.
- **Evidence requirements** — what counts as proof.
- **Output format** — JSON report, structured handoff, or both.

A contract is a runnable artifact, not a wish list. See [`templates/validation-contract.template.md`](../../templates/validation-contract.template.md).

## Workflow

1. Read the validation contract.
2. Identify each assertion and its required evidence.
3. Confirm prerequisites are satisfied.
4. Execute each assertion through the real contract surface where possible (real command, real API, real query).
5. Mark each assertion as `pass`, `fail`, `blocked`, or `skipped`.
6. Capture evidence for every result (command output, query result, screenshot, exit code).
7. Report blockers and any non-disruptive checks attempted.
8. File follow-up `bd` tasks for failures or gaps.

## Status meanings

- `pass`: observed behavior matches the contract.
- `fail`: observed behavior contradicts the contract.
- `blocked`: prerequisite unavailable or unsafe to proceed.
- `skipped`: explicitly out of scope or not applicable to this run.

## Evidence by surface

| Surface | Evidence |
| --- | --- |
| CLI | command, output summary, exit code |
| API | request, status code, response summary |
| UI | screenshot, console / network summary |
| Kubernetes | read-only command output |
| GitOps | rendered manifests, diff, sync status |
| Observability | query, time window, result summary |
| Logs | LogQL query, count, sample lines |

## Output

Use [`templates/validation-report.template.json`](../../templates/validation-report.template.json) for machine-readable reports or the standard handoff contract for human review.

## Pairing with parallel dispatch

When the same contract runs across N targets (clusters, services, dashboards), pair this skill with [`core/protocols/parallel-dispatch.md`](../../core/protocols/parallel-dispatch.md): launch N workers, each executing the contract against one target, then aggregate.

A 12-check contract run across 3 clusters in parallel completes in ~5 minutes vs ~45 minutes sequential.
