# bd and Memory Protocol

The single source of truth for task state, durable memory, the compaction lifecycle, and the post-task wrap-up. The visual lifecycle is in [`LIFECYCLE.md`](../../LIFECYCLE.md).

## Sub-agent startup checklist

At the start of every task, every sub-agent must:

1. Read this file (for bd workflow, verification, constraints).
2. Read [`references/index.md`](../../references/index.md) to discover available reference docs.
3. Read [`references/clusters.md`](../../references/clusters.md) before any cluster-scoped decision.
4. Read the **core domain learnings** file(s) named in your agent prompt.
5. Read **conditional learnings** files only when the task involves their domain.

Non-engineering sub-agents (`task-planner`, `tool-researcher`): read only the "bd Context", "Constraints", and "Learnings Protocol" sections. Skip Git Worktree, Verification, and Pre-Completion Checklist.

## bd context & coordination

- **At task start**: `bd prime` loads workflow context, persistent memories, and ready tasks. Session-start hooks run this automatically.
- **If assigned a bd task**: `bd comments <id>` to read prior agent notes. On completion: `bd comments add <id> "PR #XXXX merged. Validated on <env>. Next: ..."`.
- **On reusable insight**: `bd remember "<insight>" --key <repo>/<prefix>/<topic>`. Memories must be self-contained — what was done, what remains, bd task IDs, external ticket keys, blockers.

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

### Surgical changes

Touch only what you must. Every changed line traces to the task.

- No reformatting or refactoring adjacent code.
- No explanatory comments for obvious patterns.
- Do not include fields/defaults the existing pattern omits — explicit defaults cause permadiffs in ArgoCD.
- Match existing style exactly even if you would do it differently.
- Log unrelated issues you spot as `bd comments` or new `bd create` tasks. Do NOT fix them in your PR.

### Simplicity

Minimum code that solves the task. No features beyond what was asked. If the task says "create 5 alerts," create exactly 5.

**Infrastructure exception**: Guardrails (policy rules), alerts, and log filtering are baseline requirements for production tools, not speculative work.

### Assumptions

State assumptions before executing; log them in `bd comments`.

- Verify metric names: `curl -s <pod-ip>:<port>/metrics | grep <metric>`.
- Verify upstream values paths: `helm show values <repo>/<chart> --version <ver> | grep <path>`.
- If the task feels wrong, log the concern and proceed with your best judgment. Do NOT silently reinterpret.

### Verification

Every task ends with explicit verification.

- Helm: `helm dep build && helm lint && helm template` must succeed.
- ArgoCD: `helm template <argo-apps-release> <argo-apps-chart> -f values.<cluster>.yaml` renders correctly.
- Alerts / SLOs: PromQL syntactically valid; metric names exist in the target datasource.
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

Learnings live in [`references/learnings-*.md`](../../references/), not in agent configs. Each agent config specifies which files to load — only load what your config says. The system as a whole (index + log + learnings) follows [Andrej Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern; full rules and the `bd remember` → numbered-learning promotion path are in [`references/README.md`](../../references/README.md).

Available learnings files:

- `learnings-helm-ci.md` — YAML formatting, Helm patterns, Git, GitHub Actions, workflow pinning
- `learnings-argocd.md` — ArgoCD sync, values keys, CRD ordering
- `learnings-observability.md` — PromQL, alerting, Grafana dashboards
- `learnings-operators.md` — Operators, CRDs, policy engines
- `learnings-rollout.md` — Rollout patterns, campaigns, cross-repo coordination
- `learnings-agent-workflow.md` — Sub-agent dispatch pitfalls
- `learnings-k8s-sa.md` — ServiceAccount separation, Workload Identity, image pull secrets

Capturing a new learning: append a numbered item to the right file. Never duplicate — update the existing entry instead. If a learning is tightly coupled to one sub-agent, also add a short pointer in that agent's "Learnings tightly coupled" section.

## Task completion checklist

Before finishing any non-trivial task:

1. **Persist learnings**: `bd remember "<self-contained insight>" --key <repo>/<prefix>/<topic>`.
2. **Append one line to [`references/log.md`](../../references/log.md)**:
   ```
   ## [YYYY-MM-DD] <type> | <repo> | <one-line summary> [bd:<id>] [pr:<#>]
   ```
   Types: `rollout` | `research` | `bugfix` | `docs` | `refactor` | `upgrade` | `enablement` | `audit` | `harness`. Skip for trivial / read-only tasks.
3. **Flag conflicts**. If a finding conflicts with an existing numbered entry in a `learnings-*.md` file, include in your handoff:
   ```
   CONFLICT: <new finding> vs <file>#<item-number>
   ```
   Do NOT silently edit learnings files — the human reviews and decides.
4. **Update [`references/index.md`](../../references/index.md)** only when you add or remove a file in any indexed location.
