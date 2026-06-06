# Delegation Protocol

**Always delegate to a specialist sub-agent when one exists for the task.** Do not perform the work yourself if a matching agent is available.

## Routing

| Work type | Sub-agent |
| --- | --- |
| Project planning, task breakdown, sequencing | `task-planner` |
| Tool research, version assessment, production readiness | `tool-researcher` |
| Helm chart authoring and upgrades | `helm-engineer` |
| ArgoCD applications, per-cluster values, GitOps enablement | `argocd-engineer` |
| CI workflows, alerts, dashboards, observability | `platform-engineer` |
| Post-PR review, fix, CI feedback | `pr-reviewer` |
| General-purpose engineering: code exploration, research, analysis, parallel file edits, validation, Q&A, report generation | `general-engineer` |

## When NOT to delegate

Do the work directly when:

1. No sub-agent matches.
2. The change is trivial (one file, less than ~2 minutes).
3. A previous sub-agent already failed or timed out on the same task in this session.
4. The operation requires `rm -rf` or other deletion the orchestrator must execute itself. Sub-agents are typically blocked from destructive shell verbs by the runtime's risk gate. Use `git rm -r` as a safer alternative when applicable.

When delegating, always provide: goal, target architecture / outcome, reference files / patterns, constraints, verification criteria, expected output.

## Multi-agent orchestration

When a task spans multiple sub-agents (e.g., new tool = tool-researcher → helm-engineer → argocd-engineer → platform-engineer), the orchestrator self-chains the dispatch. Pass each agent's output as context to the next. Do NOT dispatch task-planner for orchestration — the orchestrator owns the chain.

## When a sub-agent fails or times out

1. Read the error or partial output. Identify whether it's a prompt issue, a tooling issue, or a genuine blocker.
2. Retry ONCE with a tighter, more specific prompt — add the missing context or constraint.
3. If it fails again, break the task into smaller pieces and dispatch separately.
4. If still blocked, perform the work directly and note the failure pattern via `bd remember`.

## Dispatch prompt structure

**The target architecture goes first.** Sub-agents bias toward current repo state and will ignore a buried target.

```markdown
## Goal
<one sentence>

## Target architecture / outcome
<one paragraph stating the intended end state, BEFORE any "explore the repo" instructions>

## Steps
1. <specific step>
2. <specific step>

## Reference
- <files to read first>
- <patterns to follow>

## Constraints
- <what to preserve / not touch>

## Verify by
- <command/check>: <pass/fail criterion>
- <command/check>: <pass/fail criterion>

## Expected output
<format: PR, structured report, file at path, etc.>

## Memory
Before finishing:
bd remember "<insight>" --key <repo>/<prefix>/<topic>
```

**Every dispatch must include `Verify by:`.** Vague tasks produce vague results. Concrete examples:

- `helm template` succeeds without rendering errors.
- Metric names match `/metrics` endpoint output.
- PR diff contains only files in `charts/<name>/`.
- Pods Ready, zero restarts, operator logs clean.

## Include this in every dispatch prompt

Append this block to every sub-agent dispatch. It primes the sub-agent on shared protocols, knowledge sources, and the memory contract:

```markdown
## Reference loading
- Read `core/protocols/bd-and-memory.md` for shared protocols (code quality, bd, verification, completion).
- Read `references/index.md` to discover available reference docs.
- Search `bd memories <keywords>` for task-relevant prior art.
- Read `references/clusters.md` (or the repo equivalent) for cluster details, if the task is cluster-scoped.
- If `graphify-out/graph.json` exists in the repo, load it for architecture and dependency questions.
- **Prior art citation**: Before implementing, grep learnings files for prior art on your task keywords. If a learnings entry is relevant, cite it as `[learnings-<file>.md#<N>]` in your output and build on it rather than re-deriving.

## Memory
Before finishing, persist any non-obvious findings:
bd remember "<insight>" --key <repo>/<prefix>/<topic>
```

This is non-negotiable. Sub-agents that skip the reference-loading step routinely:
- re-implement utilities that already exist (Reuse-First violations),
- contradict numbered learnings entries with conflicting fixes,
- miss cluster-specific constraints documented in `clusters.md`.

The block is short, paste-friendly, and the cost of including it is zero.

## Subagent-specific dispatch tips

- **For `tool-researcher`**: state the deployment model explicitly at the top (e.g. "We deploy as 4 independent ArgoCD apps, NOT a single umbrella chart"). Buried targets get ignored.
- **For `pr-reviewer`**: pass the PR URL, original task summary, key files, and any preserve constraints. Use a different model from the creating sub-agent when the runtime supports it.
- **For amending PRs**: tell the sub-agent about the open PR, branch name, and worktree path explicitly. They will not discover them on their own.

## Parallel dispatch

When the same playbook runs across N independent targets (clusters, services, charts, dashboards), see [`parallel-dispatch.md`](parallel-dispatch.md): one playbook, N workers launched in a single message, aggregation in the orchestrator.

## Knowledge consolidation

On every session start or resume, the orchestrator checks if bd memories need consolidating into learnings files:

1. Run `bd memories consolidation` to find the `<repo>/meta/last-consolidation` memory.
2. If missing or older than 7 days, suggest to the user: "Last knowledge consolidation was N days ago (or never). Want me to consolidate?"
3. If approved, dispatch `general-engineer` with the consolidation workflow:
   - Read all bd memories
   - For each memory with prefix `<repo>/decision`, `<repo>/lesson`, `<repo>/trouble`, `<repo>/tool`: check if it exists in the matching learnings file
   - If not present and reusable, append as numbered item
   - Update `index.md` if new files created
   - Run: `bd remember "last consolidation: <date>, promoted N memories" --key <repo>/meta/last-consolidation`

Do NOT auto-run without user approval.

## PR review dispatch rules

After any sub-agent returns a PR URL, evaluate whether to dispatch `pr-reviewer`. See the full matrix in [`pr-review-loop.md`](pr-review-loop.md). Summary:

**Always dispatch for**: Helm chart, ArgoCD, CI/alerting/observability changes, PRs touching >5 files or >100 lines, security-sensitive paths (secrets, RBAC, NetworkPolicies, escalation policies).

**Never dispatch for**: docs-only PRs, single-file config value changes (<10 lines), or when the user says "skip review."

**Use judgment for**: 3–5 files / 50–100 lines (dispatch if logic, skip if scaffolding); general-engineer PRs (dispatch if the original task was non-trivial).
