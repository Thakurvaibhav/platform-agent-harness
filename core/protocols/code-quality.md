# Code Quality & Engineering Standards

The single canonical home for coding guidelines and engineering standards. **Every engineering sub-agent and the main session follows this** (non-engineering agents like `task-planner` may skip it — see the startup checklist in [`bd-and-memory.md`](bd-and-memory.md)). Other protocols reference this file; they do not restate it.

## Assumptions

**Don't assume. Don't hide confusion. Surface tradeoffs.**

- State assumptions explicitly before executing; log them in `bd comments`.
- If multiple valid interpretations exist, present them — don't pick silently.
- If a simpler approach exists than what was requested, say so.
- If confused, stop and name what's unclear. Never fabricate context.
- Before starting work that might have prior art (rollout, research, upgrade, playbook), check [`agent-knowledge/references/index.md`](../../agent-knowledge/references/index.md) for an existing doc on the topic. Read the relevant doc before writing anything from scratch.
- Verify metric names: `curl -s <pod-ip>:<port>/metrics | grep <metric>`.
- Verify upstream values paths: `helm show values <repo>/<chart> --version <ver> | grep <path>`.
- If the task feels wrong, log the concern and proceed with your best judgment. Do NOT silently reinterpret.

## Simplicity

Minimum code that solves the task. Nothing speculative.

- No features or templates beyond what was asked. If the task says "create 5 alerts," create exactly 5.
- No abstractions for single-use code. No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you wrote 200 lines and it could be 50, rewrite it.
- Test: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

**Reuse-first.** Before writing any new function, utility, or pattern — search the codebase for an existing one.

1. **Search first**: grep keywords in `utils/`, `helpers/`, `common/`, `shared/`, `lib/` and across the repo.
2. **Reuse or extend**: if something similar exists, use it. If close but not exact, extend it — don't fork a parallel implementation.
3. **Document if new**: place it where future code can find it (shared module, not buried in a feature directory).

Blocking violations: creating a function that duplicates >80% of an existing one; reimplementing a utility that already lives in a shared module; ignoring existing naming conventions, error handling patterns, or config approaches.

Reject these rationalizations: "My version is slightly different" (extend instead), "The existing code is messy" (refactor separately), "It's faster to rewrite" (maintaining two versions is slower forever).

**Infrastructure exception**: guardrails (policy rules), alerts, and log filtering are baseline requirements for production tools, not speculative work.

## Surgical changes

Touch only what you must. Every changed line traces to the task.

- No reformatting or refactoring adjacent code.
- **Comments: terse, and only for a non-obvious *why*.** A comment explains *why* (a real constraint, gotcha, or deliberate deviation) — it NEVER restates *what* the code already says. Match the surrounding comment density; if the neighboring code has no comments, add none. One line where one line works — no multi-sentence essays, no step-by-step narration, no changelog prose in the source.
- **No ticket IDs, PR numbers, dates, or author names in code comments.** Issue keys (`<TICKET-123>`), PR links, and "added on `<date>`" belong in the **commit message and PR description**, NOT the source — they rot, add noise, and leak internal references into shared/public code. Tempted to write `# <TICKET-123>: does X`? Put the ticket in the PR body; the comment (if any) states only the non-obvious *why*.
- Do not include fields/defaults the existing pattern omits — explicit defaults cause permadiffs in ArgoCD.
- Match existing style exactly even if you would do it differently.
- Remove only imports/variables/functions that YOUR changes made unused. Do not remove pre-existing dead code unless the task asks for it.
- Log unrelated issues you spot as `bd comments` or new `bd create` tasks. Do NOT fix them in your PR.

## Verification (goal-driven execution)

Define success criteria. Loop until verified. Every task ends with explicit verification.

Transform tasks into verifiable goals:

- "Add validation" → write tests for invalid inputs, then make them pass.
- "Fix the bug" → write a test that reproduces it, then make it pass.
- "Refactor X" → ensure tests pass before and after.

For multi-step tasks, state a brief plan:

```
1. [step] → verify: [check]
2. [step] → verify: [check]
```

Domain-specific checks:

- Helm: `helm dep build && helm lint && helm template` must succeed.
- ArgoCD: `helm template <argo-apps-release> <argo-apps-chart> -f values.<cluster>.yaml` renders correctly.
- Alerts: PromQL syntactically valid; metric names exist in the target datasource.
- Enablement: pods Ready, zero restarts, operator logs clean (see Post-Deploy Validation in [`safety-and-handoff.md`](safety-and-handoff.md)).

## Standing engineering reflexes

Apply on context, no prompt needed. These fire alongside any verification work.

**R1 — Offline proof before "done" (and before live testing).** For any change whose effect can be rendered or simulated, reproduce the NEW behavior offline and diff against current BEFORE claiming it works: `helm template` / `egctl x translate` / admission dry-run / `kubectl --dry-run`. Cite the artifact (the diff, the rendered output). Live testing is confirmation, not first evidence. Include a negative control where feasible (mutate one input; the check must catch it). Skip only for trivial edits where behavior isn't in question.

**R2 — Read the source for third-party behavior.** Any claim about how a third-party tool (plugin, controller, operator, library) behaves at runtime must be backed by its SOURCE at the version you run — read it and cite `file:line`. Docs and issues are secondary and often stale. Skip only when the behavior isn't in question.

**R3 — Upstream triage.** On a confirmed third-party limitation/bug, search its issues/PRs, judge whether it's tracked + the project's health, and if untracked-and-costly, draft a generic (no internal names) upstream issue. DRAFT and CONFIRM before filing — never auto-file.

**R4 — Stakeholder-aware comms.** For any team-facing message about a decision/tradeoff/change: acknowledge prior sign-offs, present options neutrally (value before cost), position yourself as ready-either-way (not blocking), make complexity concrete but blame-free, redact internal info from external-facing, link external docs.
