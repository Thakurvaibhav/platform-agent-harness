# Code Quality & Engineering Standards

The single canonical home for coding guidelines and engineering standards. **Every engineering sub-agent and the main session follows this** (non-engineering agents like `task-planner` may skip it — see the startup checklist in [`bd-and-memory.md`](bd-and-memory.md)). Other protocols reference this file; they do not restate it.

## Assumptions

- If confused, stop and name what's unclear. Never fabricate context.
- Before starting work that might have prior art (rollout, research, upgrade, playbook), check [`agent-knowledge/references/index.md`](../../agent-knowledge/references/index.md) for an existing doc on the topic. Read the relevant doc before writing anything from scratch.
- Verify metric names: `curl -s <pod-ip>:<port>/metrics | grep <metric>`.
- Verify upstream values paths: `helm show values <repo>/<chart> --version <ver> | grep <path>`.
- If the task feels wrong, log the concern and proceed with your best judgment. Do NOT silently reinterpret.

## Simplicity

Minimum code that solves the task. Nothing speculative.

- No features or templates beyond what was asked. If the task says "create 5 alerts," create exactly 5.
- No abstractions for single-use code. No "flexibility" or "configurability" that wasn't requested.
- Test: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

**Reuse-first.** Before writing any new function, utility, or pattern — search the codebase for an existing one.

1. **Search first — in the shape the repo actually has.** For application code: `utils/`, `helpers/`, `common/`, `shared/`, `lib/`. **In an infrastructure repo those directories often do not exist** — one Helm monorepo has zero `utils/`, `common/`, `shared/` or `lib/` directories and 141 `_helpers.tpl` files. Grepping the canonical list, finding nothing, and calling that diligence is the most common way this rule gets satisfied without being followed. In a chart, search:
   - the chart's own `_helpers.tpl` — the define you need usually already exists,
   - every level of `values.yaml` for the key you are about to add (`grep -n '<key>:'`) — a duplicate key at a second level silently wins or loses by YAML ordering,
   - **the chart's structural shape** — component-keyed (`<chart>.components.<name>`) vs flat. Writing a flat singleton into a component-keyed chart is a rewrite, not a tweak.
2. **Reuse or extend**: if something similar exists, use it. If close but not exact, extend it — don't fork a parallel implementation.
3. **Document if new**: place it where future code can find it (shared module, not buried in a feature directory).

Blocking violations: creating a function that duplicates >80% of an existing one; reimplementing a utility that already lives in a shared module; ignoring existing naming conventions, error handling patterns, or config approaches.

Reject these rationalizations: "My version is slightly different" (extend instead), "The existing code is messy" (refactor separately), "It's faster to rewrite" (maintaining two versions is slower forever).

**Infrastructure exception**: guardrails (policy rules), alerts, and log filtering are baseline requirements for production tools, not speculative work.

## Surgical changes

Touch only what you must. Every changed line traces to the task.

- No reformatting or refactoring adjacent code.
- **Comments: the default is NONE.** Code says *what*. A comment exists only when there is a non-obvious *why* — a real constraint, a gotcha, a deliberate deviation. If you cannot name that why in one line, there probably isn't one. Match the surrounding density: if the neighbouring code carries no comments, add none. A comment that restates the code is worse than no comment — it is a second thing to keep true.
- **No ticket IDs, PR numbers, dates, or author names in code comments.** Issue keys (`<TICKET-123>`), PR links, and "added on `<date>`" belong in the **commit message and PR description**, NOT the source — they rot, add noise, and leak internal references into shared/public code. Tempted to write `# <TICKET-123>: does X`? Put the ticket in the PR body; the comment (if any) states only the non-obvious *why*.
- **Ceiling: 2 lines per comment block** when one is warranted. A third line means it is PR-description material, not source. This is a count, not a call — "terse" and "one line where one line works" are judgments, and every author of a 10-line block believes theirs is the justified exception. **Relocate** the rationale to the PR body; do not delete it.
- **Gate it, don't eyeball it:** [`core/hooks/generic/comment-discipline.sh`](../hooks/generic/comment-discipline.sh) checks all three rules against a diff (banned refs, block length, per-file density) (`--staged`, `--base <ref>`, or a diff on stdin); exit 1 = findings. The `create-pr` skill runs it before push and `pr-reviewer` runs it at review. The prose version of these two rules alone was not enough — real PRs shipped 10-line comment blocks carrying issue keys, twice, including once through a manual correction pass. A line count cannot be argued with; an adjective can.
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

### Checks that measure something

A check that measures by grepping a tool's human-readable output silently becomes a no-op when that tool changes its format — and it fails in the reassuring direction. Three of this harness's own gates carried that defect at once: two memory-bloat guards that counted with `grep -c` against output the tool had stopped emitting, and a usage counter that credited a read whenever a filename *appeared*, so a file that had never existed outranked three real ones. All three reported health.

- **Count from a machine-readable surface** (`--json`, `-o jsonpath`, an API), never from formatted text. Formatted output is a UI; it changes without notice and without an error.
- **Measure the outcome, not the intent.** A tool call is emitted whether or not it succeeded; a filename in a command may be what is being *searched for* rather than read. Assert the thing actually happened — the file exists, the resource is there, the count came back.
- **Distinguish zero from could-not-measure.** Return a sentinel when the measurement itself fails and WARN on it. A check that could not run must never render as a pass.
- **Test every threshold check with a control that forces it to fire**, plus one that breaks the measurement. A gate whose failure mode is silence is indistinguishable from a healthy system, so a green run proves nothing until you have seen the gate go red on demand.

This is the same non-vacuity requirement R1 states for rendered changes, applied to the checks themselves: a threshold that has never fired has not been shown capable of firing, exactly as a validation suite that cannot fail is indistinguishable from a perfect one. See [`learnings-validation-framework.md`](../../agent-knowledge/references/learnings-validation-framework.md) items 23 ("absence reads as pass" at every layer) and 24 (prove non-vacuity; one known-bad input per question the tool asks).

## Standing engineering reflexes

Apply on context, no prompt needed. These fire alongside any verification work.

**R1 — Offline proof before "done" (and before live testing).** For any change whose effect can be rendered or simulated, reproduce the NEW behavior offline and diff against current BEFORE claiming it works: `helm template` / `egctl x translate` / admission dry-run / `kubectl --dry-run`. Cite the artifact (the diff, the rendered output). Live testing is confirmation, not first evidence. Include a negative control where feasible (mutate one input; the check must catch it). Skip only for trivial edits where behavior isn't in question.

**R2 — Read the source for third-party behavior.** Any claim about how a third-party tool (plugin, controller, operator, library) behaves at runtime must be backed by its SOURCE at the version you run — read it and cite `file:line`. Docs and issues are secondary and often stale. Skip only when the behavior isn't in question.

**R3 — Upstream triage.** On a confirmed third-party limitation/bug, search its issues/PRs, judge whether it's tracked + the project's health, and if untracked-and-costly, draft a generic (no internal names) upstream issue. DRAFT and CONFIRM before filing — never auto-file.

**R4 — Stakeholder-aware comms.** For any team-facing message about a decision/tradeoff/change: acknowledge prior sign-offs, present options neutrally (value before cost), position yourself as ready-either-way (not blocking), make complexity concrete but blame-free, redact internal info from external-facing, link external docs.
