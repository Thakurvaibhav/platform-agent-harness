# bd and Memory Protocol

The single source of truth for task state, durable memory, the compaction lifecycle, and the post-task wrap-up. The visual lifecycle is in [`LIFECYCLE.md`](../../LIFECYCLE.md).

## Sub-agent startup checklist

At the start of every task, every sub-agent must:

1. Read this file (for bd workflow, verification, constraints).
2. Read [`references/index.md`](../../references/index.md) to discover available reference docs, project documentation, and topic learnings. From the "Topic learnings" table, load every learnings file whose domain overlaps with your assigned task. When uncertain, load it.
3. Search `bd memories <keywords>` for task-relevant prior art (use 2-3 keywords from your task). bd memories contain operational state, decisions, and gotchas that may not be in learnings files yet.
4. Read [`references/clusters.md`](../../references/clusters.md) (or the repo equivalent) before any cluster-scoped decision.

Non-engineering sub-agents (`task-planner`, `tool-researcher`): read Constraints, bd context, Learnings protocol, Task completion checklist, and the Handoff contract (in [`safety-and-handoff.md`](safety-and-handoff.md)). Skip Code quality principles, Git worktree protocol, Amending existing PRs, Base pre-completion checklist, and Post-deploy validation.

## bd context & coordination

- **At task start**: `bd prime` loads workflow context, persistent memories, and ready tasks. Session-start hooks run this automatically.
- **If assigned a bd task**: `bd comments <id>` to read prior agent notes. On completion: `bd comments add <id> "PR #XXXX merged. Validated on <env>. Next: ..."`.
- **On reusable insight**: `bd remember "<insight>" --key <repo>/<prefix>/<topic>`. Memories must be self-contained — what was done, what remains, bd task IDs, external ticket keys, blockers.

## Pre-compaction / context-loss checkpoint

The pre-compaction hook ([`core/hooks/factory-droid/pre-compact-bd-sync.py`](../hooks/factory-droid/pre-compact-bd-sync.py)) snapshots state automatically before auto/manual compaction, but **do not rely on it alone**. Checkpoint deliberately whenever context is high, a long turn is ending, or a task has meaningful in-flight state.

Before compaction or any handoff-prone pause:

1. Run `bd remember "<self-contained current state: decisions, blockers, PRs, bd IDs, next action>" --key <repo>/pre-compact` from the repo root.
2. If working a bd task, add `bd comments add <id> "Checkpoint: <current state and next action>"`.
3. If a reusable operational lesson emerged, add or update the relevant `learnings-*.md` entry **in the same session** — don't wait for final task completion.
4. If `bd remember` fails with "no beads database found", change to the repo root (the directory that owns `.beads/`) and retry before continuing.

The hook is the safety net; the deliberate checkpoint is what captures the *reasoning* the hook can't infer from the transcript.

## Memory key taxonomy

Use these prefixes consistently so memories are categorizable and searchable.

| Prefix | Use for | Example |
| --- | --- | --- |
| `<repo>/decision/<topic>` | Architectural choices, why X over Y | `bd remember "chose Gateway API over Ingress for multi-tenant routing" --key <repo>/decision/gateway-api` |
| `<repo>/infra/<topic>` | Cluster/resource facts, sizing, limits | `bd remember "<tool> needs 512Mi memory on large-node clusters" --key <repo>/infra/<tool>-memory` |
| `<repo>/trouble/<topic>` | Resolved issues, root causes, fixes | `bd remember "cert-manager webhook timeout: fix by restarting cainjector pod" --key <repo>/trouble/cert-manager-webhook` |
| `<repo>/tool/<topic>` | Tool research outcomes, version notes | `bd remember "vector 0.43 drops lua transform, use VRL instead" --key <repo>/tool/vector-043` |
| `<repo>/lesson/<topic>` | Post-incident or post-task learnings | `bd remember "always check CRD version compatibility before helm upgrade" --key <repo>/lesson/crd-compat` |
| `<repo>/pref/<topic>` | User preferences, workflow conventions | `bd remember "user prefers kustomize over raw manifests for overlays" --key <repo>/pref/kustomize` |
| `<repo>/security/<topic>` | Security findings, CVEs, RBAC issues | `bd remember "tetragon needs NET_ADMIN cap for eBPF hooks" --key <repo>/security/tetragon-caps` |
| `<repo>/perf/<topic>` | Performance findings, sizing, benchmarks | `bd remember "vector 2x memory under burst; set limit to 2Gi" --key <repo>/perf/vector-memory` |

Replace `<repo>` with the actual repo name. The memory text must be **self-contained** — readable without the current session's chat history.

## Rules for memories

1. Self-contained: a future session must understand it without context.
2. Actionable: capture root causes and fixes, not just symptoms.
3. Don't store trivial facts (e.g. "ran `helm template` successfully"). Store things future sessions would benefit from.
4. No secrets, no tokens, no real customer / internal URLs.

## bd task workflow

```bash
bd init --prefix <repo>           # one-time per repo
bd prime                          # at session start (auto via hook)
bd ready                          # find your next unblocked task
bd update <id> --claim
bd comments <id>                  # read prior context
bd comments add <id> "<status>"   # log progress
bd dep add <blocked> <blocker> --type blocks
bd remember "<insight>" --key <repo>/<prefix>/<topic>
bd close <id> --reason "<PR created and CI passing>"
```

**Never** use `bd edit` — it opens `$EDITOR` and blocks non-interactive agents. Use `bd update <id> --title/--description/--notes` instead.

## Code quality principles

### Assumptions

**Don't assume. Don't hide confusion. Surface tradeoffs.**

- State assumptions explicitly before executing; log them in `bd comments`.
- If multiple valid interpretations exist, present them — don't pick silently.
- If a simpler approach exists than what was requested, say so.
- If confused, stop and name what's unclear. Never fabricate context.
- Before starting work that might have prior art (rollout, research, upgrade, playbook), check [`references/index.md`](../../references/index.md) for an existing doc on the topic. Read the relevant doc before writing anything from scratch.
- Verify metric names: `curl -s <pod-ip>:<port>/metrics | grep <metric>`.
- Verify upstream values paths: `helm show values <repo>/<chart> --version <ver> | grep <path>`.
- If the task feels wrong, log the concern and proceed with your best judgment. Do NOT silently reinterpret.

### Simplicity

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

### Surgical changes

Touch only what you must. Every changed line traces to the task.

- No reformatting or refactoring adjacent code.
- No explanatory comments for obvious patterns.
- Do not include fields/defaults the existing pattern omits — explicit defaults cause permadiffs in ArgoCD.
- Match existing style exactly even if you would do it differently.
- Remove only imports/variables/functions that YOUR changes made unused. Do not remove pre-existing dead code unless the task asks for it.
- Log unrelated issues you spot as `bd comments` or new `bd create` tasks. Do NOT fix them in your PR.

### Verification (goal-driven execution)

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
- Enablement: pods Ready, zero restarts, operator logs clean (see Post-Deploy Validation Protocol below).

## Git worktree protocol

Never work in the main checkout. Always use a git worktree.

```bash
cd <repo-path>
git fetch origin main
git worktree add ../<repo>-<branch-name> -b <branch-name> origin/main
cd ../<repo>-<branch-name>
# ...work...
# After merge:
git worktree remove ../<repo>-<branch-name>
```

Check `git worktree list` first — reuse an existing worktree if suitable.

Edge cases:

- After `gh pr merge`, delete the remote branch AND `git worktree remove ../<dir>`. Stale worktrees accumulate.
- Rebasing inside a worktree: `git fetch origin main && git rebase origin/main`. Force-push with `--force-with-lease`.

## Amending existing PRs

When asked to make a change and an open PR for related work exists, prefer amending over a new PR:

```bash
gh pr list --head <branch-name>
```

If an open PR exists and the change is related: reuse the worktree/branch, amend, force-push (with `--force-with-lease`). Only create a separate PR if the changes are truly unrelated.

**Dispatch hint**: when you (orchestrator) want a sub-agent to amend, explicitly pass the PR number, branch name, and worktree path — sub-agents don't discover open PRs on their own.

## Base pre-completion checklist

Run before creating a PR. Domain-specific checks add to this.

1. **Formatting**: no trailing blank lines, single trailing newline, `yamlfmt --lint` passes on changed YAML.
2. **Helm validation**: `helm dep build`, `helm lint`, `helm template` succeed on every chart you modified.
3. **No secrets in diff**: `git diff` shows no credentials, tokens, API keys.
4. **PR description**: external ticket link and rationale (WHY, not just WHAT).

## Post-deploy validation

After any tool/chart is deployed or enabled on a cluster, validate:

1. **Pods running**: `kubectl get pods -n <ns> --context <cluster>` — all Ready, zero restarts.
2. **Operator logs clean**: grep for `error|warn|fail|panic` in operator pod logs.
3. **Agent/DaemonSet logs**: same grep. DaemonSets have one pod per node — many pods on large clusters is normal.
4. **CRDs created** (operators): `kubectl get crd --context <cluster> | grep <tool>`.
5. **Custom Resource conditions**: check CR status directly — ArgoCD "Synced/Healthy" does NOT mean CRs reconcile correctly.
6. **Metrics flowing**: verify data appears in Grafana if the tool exposes metrics.

## Constraints (all engineering sub-agents)

- NEVER run mutating kubectl or helm commands. Read-only (`get`, `describe`, `logs`, `top`) is allowed.
- NEVER push to `main` / `master`. Always feature branches.
- NEVER force-push protected branches.
- NEVER add "merge when ready" labels to PRs — human review first.

## Learnings protocol (short form)

Learnings live in [`references/learnings-*.md`](../../references/), not in agent configs. Agents discover relevant files via [`references/index.md`](../../references/index.md) at startup (step 2) — no hardcoded lists in agent configs. Additionally, `bd memories` (step 3) contain operational knowledge that may not yet be in learnings files. The system as a whole (index + log + learnings) follows [Andrej Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern; full rules and the `bd remember` → numbered-learning promotion path are in [`references/README.md`](../../references/README.md).

**Primary write path:** `bd remember` on every non-trivial task (mandatory). Learnings file updates when a clear reusable pattern emerged (recommended). Periodic consolidation from bd memories to learnings files is handled by the orchestrator.

Capturing a new learning: append a numbered item to the right file. Never duplicate — update the existing entry instead. If a learning is tightly coupled to one sub-agent, also add a short pointer in that agent's "Learnings tightly coupled" section.

## Task completion checklist

Before finishing any non-trivial task:

1. **bd remember** — operational state (mandatory):
   ```bash
   bd remember "<self-contained insight>" --key <repo>/<prefix>/<topic>
   ```
2. **Learnings files** (recommended when a clear reusable pattern emerged — not required on every task):
   - Update the matching `learnings-*.md` file (find it via [`references/index.md`](../../references/index.md)).
   - Search the file first — never duplicate. Update in place if similar exists.
   - Append as next numbered item. Be specific: include file paths, commands, error messages.
   - If no file matches, store via `bd remember` and flag in handoff report.
   - **Graduation rule:** If a learning in your agent's "Learnings tightly coupled" section would benefit other agents, move it to the shared learnings file.
3. **[`references/index.md`](../../references/index.md)** — update only when you add or remove a file in any indexed location.

Additionally:

- Append one line to [`references/log.md`](../../references/log.md) (format unchanged, skip for trivial / read-only tasks):
  ```
  ## [YYYY-MM-DD] <type> | <repo> | <one-line summary> [bd:<id>] [pr:<#>]
  ```
  Types: `rollout` | `research` | `bugfix` | `docs` | `refactor` | `upgrade` | `enablement` | `audit` | `harness`.
- **Flag conflicts.** If a finding conflicts with an existing numbered entry in a `learnings-*.md` file, include in your handoff:
  ```
  CONFLICT: <new finding> vs <file>#<item-number>
  ```
  Do NOT silently edit learnings files — the human reviews and decides.
