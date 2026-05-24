# Worked Example: Helm Chart Upgrade

End-to-end flow upgrading the `<example-operator>` Helm chart from `1.4.0` to `1.6.0` in a GitOps repo. Demonstrates the full harness: planning, research, implementation, review, validation, memory.

This is illustrative — placeholders use generic names like `<example-operator>`, `<cluster>`, `<repo>`. No real org-specific values appear.

---

## 0. Initial trigger

User in the main session:

> "We need to bump the `<example-operator>` chart to 1.6.0. There are CRD changes in 1.5 we need to think about."

Main session activates the `task-planner` (via the runtime's delegation mechanism).

## 1. Planning (`task-planner`)

`task-planner` reads:

- [`references/index.md`](../references/index.md) — looks for prior `<example-operator>` learnings. Finds two:
  - `learnings-helm-ci.md#3`: "Always run `helm dep build` before lint/template."
  - `learnings-rollout.md#2`: "Operator upgrades touching CRDs need phased per-env rollout."
- [`references/clusters.md`](../references/clusters.md) — confirms `<example-operator>` is enabled on `<dev>`, `<stag>`, `<prod>` clusters.
- Existing chart at `charts/<example-operator>/Chart.yaml` — currently pinned to `1.4.0`.

Plan presented to user:

| # | Task | Sub-agent | Depends on |
| - | --- | --- | --- |
| 1 | Research `<example-operator>` 1.4.0 → 1.6.0 (breaking changes, CRDs, values) | `tool-researcher` | — |
| 2 | Bump chart version, migrate values, render diff | `helm-engineer` | 1 |
| 3 | Add per-cluster `enable: true` overrides for `<dev>` only | `argocd-engineer` | 2 |
| 4 | PR review with bot replies | `pr-reviewer` | 2 |
| 5 | Promote to `<stag>` after 24h soak | `argocd-engineer` | 3 |
| 6 | Promote to `<prod>` after 24h `<stag>` soak | `argocd-engineer` | 5 |

User approves. `task-planner` creates 6 bd tasks with dependencies.

```bash
bd create "Research <example-operator> 1.6.0 upgrade" -t task -d "[Ticket: PROJ-1234]"
bd create "Bump <example-operator> to 1.6.0" -t task -d "[Ticket: PROJ-1234]"
bd dep add <bump-task> <research-task> --type blocks
# ... etc
```

## 2. Research (`tool-researcher`)

Dispatched with target architecture FIRST:

```
## Target architecture / outcome
We deploy <example-operator> as a single Helm chart wrapping the upstream
chart. We need a production-readiness assessment for 1.6.0, NOT a fresh
deployment design.

## Goal
Identify breaking changes between 1.4.0 and 1.6.0, values migration steps,
CRD changes, and integration concerns.
```

Returns a structured production-readiness report:

```markdown
# Production Readiness Report: <example-operator> 1.6.0

## Summary
1.6.0 is GA, recommended. One CRD field rename in 1.5, one breaking
values-path change. Migration is mechanical.

## Breaking changes
- 1.5.0: CRD field `spec.policy.mode` renamed to `spec.policy.action`.
- 1.6.0: values key `controller.metrics.port` renamed to `metrics.port`.

## CRDs
- New CRD `MetricsExporter` added in 1.6.0.
- Existing `Policy` CRD: field rename only, no schema break.

## Recommended next steps
helm-engineer:
  - Rename `controller.metrics.port` to `metrics.port` in values.
  - Confirm no in-repo `Policy` CRs use `spec.policy.mode`.
argocd-engineer:
  - Phased rollout: <dev> first, then <stag>, then <prod>.
```

Logged: `bd remember "<example-operator> 1.5+ renamed spec.policy.mode to spec.policy.action; not a schema break" --key <repo>/upgrade/<example-operator>-1.6`.

## 3. Implementation (`helm-engineer`)

Dispatched with the production-readiness report attached:

```markdown
## Target architecture / outcome
Wrapper chart `charts/<example-operator>` bumped to 1.6.0. Values renamed
per the readiness report. No enablement changes — that is a separate PR.

## Verify by
- helm dep build charts/<example-operator>: clean
- helm lint charts/<example-operator>: clean
- helm template <release> charts/<example-operator> -f charts/<example-operator>/values/environments/dev.yaml: renders, includes metrics.port=9090
- Render diff vs 1.4.0: no immutable field changes
```

`helm-engineer` runs:

```bash
# bump dependency version
yq -i '.dependencies[0].version = "1.6.0"' charts/<example-operator>/Chart.yaml
helm dep build charts/<example-operator>

# values migration
sed -i.bak 's|controller.metrics.port|metrics.port|g' charts/<example-operator>/values.yaml
rm charts/<example-operator>/values.yaml.bak
yamlfmt charts/<example-operator>/values.yaml

# render diff
helm template <release> charts/<example-operator> -f charts/<example-operator>/values/environments/dev.yaml > /tmp/after.yaml
git diff --no-index -- /tmp/before.yaml /tmp/after.yaml | less

# confirm pulled chart identity
tar -tzf charts/<example-operator>/charts/<example-operator>-1.6.0.tgz | head
```

Render diff shows: no immutable field changes, no `Service.spec.clusterIP` change, new `MetricsExporter` CRD picked up by upstream.

PR opened via the [`create-pr` skill](../skills/create-pr/SKILL.md):

```
Title: Bump <example-operator> chart 1.4.0 → 1.6.0 (CRD + values migration)
Body:
  ## Why
  Picks up the new MetricsExporter CRD and fixes the deprecated metrics
  values path. Tracked in PROJ-1234.

  ## What changed
  - charts/<example-operator>/Chart.yaml: 1.4.0 → 1.6.0
  - charts/<example-operator>/values.yaml: controller.metrics.port → metrics.port
  - charts/<example-operator>/Chart.lock: regenerated via `helm dep build`

  ## Validation
  - helm lint: pass
  - helm template (dev values): pass, MetricsExporter CRD rendered
  - render diff: no immutable field changes

  ## Ticket
  - PROJ-1234

  ## Risk
  Low. CRD field rename in 1.5 affects no in-repo `Policy` CRs (verified).
```

Logged: `bd remember "<example-operator> 1.6 values migration: controller.metrics.port → metrics.port" --key <repo>/upgrade/<example-operator>-1.6-values`.

## 4. PR Review (`pr-reviewer`)

Main session dispatches `pr-reviewer` per the [PR review loop matrix](../core/protocols/pr-review-loop.md) — Helm chart change → **always dispatch**.

`pr-reviewer` waits up to 10 minutes for `coderabbitai[bot]` and `cursor[bot]` to post, then runs the review checklist. CodeRabbit flags one missing `values.yaml` comment explaining the rename. Reviewer pushes a one-line comment fix in iteration 1 and replies:

```
Fixed in abc1234. Added rename rationale at line 47.
```

CI passes. Summary comment posted. PR ready for human review.

## 5. Enablement (`argocd-engineer`)

After PR merge, `task-planner` releases the next task. `argocd-engineer` adds:

```yaml
# charts/<argo-apps>/values.<dev-cluster>.yaml
exampleOperator:
  enable: true
```

Single-cluster scope. PR follows the same review loop. After merge, ArgoCD syncs.

## 6. Post-deploy validation

Following [`core/protocols/bd-and-memory.md` post-deploy section](../core/protocols/bd-and-memory.md):

```bash
rtk kubectl get pods -n <example-operator> --context <dev-cluster>
rtk kubectl get crd --context <dev-cluster> | grep example
rtk kubectl logs -n <example-operator> deploy/<example-operator>-controller --context <dev-cluster> --tail=200 | grep -E 'error|warn|fail'
rtk gcx --agent metrics query -d <prom-uid> 'up{job="<example-operator>"}' -o json --since 5m
```

All Ready, zero restarts, `up=1`, no operator errors.

`bd close <enablement-task> --reason "PR #5678 merged. <dev-cluster> validated. <stag> task unblocked."`

## 7. Compaction (asynchronous)

Mid-session, the context window crosses 85%. [`ctx-threshold-warn.py`](../core/hooks/factory-droid/ctx-threshold-warn.py) injects a nudge. User runs `/compact`. The [`pre-compact-bd-sync.py`](../core/hooks/factory-droid/pre-compact-bd-sync.py) hook:

- Extracts PRs `#5677` and `#5678`, bd tasks, and ticket PROJ-1234 from the transcript.
- Writes `session/pre-compact` memory with the snapshot.
- Adds a snapshot comment to every in-progress bd task.

Next session, the new agent runs `bd prime` and sees:

- The `<example-operator>` upgrade memories.
- The in-progress `<stag>` enablement task with the snapshot comment.
- The ready `<prod>` task blocked on `<stag>` soak.

No context loss. Work resumes.

---

## What this exercised

- `task-planner` for breakdown, dispatch, retro.
- `tool-researcher` for production-readiness research.
- `helm-engineer` for the chart change.
- `argocd-engineer` for phased enablement.
- `pr-reviewer` for second-pass review with bot replies.
- `bd` for task state, comments, durable memory.
- `rtk` for read-only verbose commands.
- `gcx` for post-deploy validation.
- The pre-compact / post-compact hooks for surviving context resets.

Six sub-agents, four tools, three pillars (planning, validation, memory) — one PR shipped without losing context mid-session.
