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

### Review depth tiers

The reviewer self-triages (its Step 0.5), but name the tier you expect in the dispatch prompt so a mismatch surfaces. Effort scales with blast radius:

- **sensitive** — RBAC, secrets, NetworkPolicy, admission/policy controllers, CRD/operator config, any production-cluster manifest, auth/ingress filter config. Gets **rendered proof + cross-model verify** of every blocking finding. Prefer a stronger reviewer model when the runtime supports it.
- **standard** — everything else non-trivial; rendered proof required if it touches chart templates or values.
- **trivial** — see *Never dispatch*.

### Review style: single vs Parallax

The reviewer runs in one of two styles (its **Operating modes**), set independently from the tier:

- **Parallax** (default for standard/sensitive) — two independent model lenses on the same PR, posted as **two separately-branded reviews**:
  - **🔍 correctness lens (Claude)** — the reviewer's own pass (claims, wiring, conventions, rendered proof; refute stale bot findings).
  - **🧨 adversarial lens (Codex)** — an independent [`agent-knowledge/scripts/codex-dispatch.sh`](../../agent-knowledge/scripts/codex-dispatch.sh) pass in a read-only worktree at the merge-base that tries to *break* head against the PR's claims (helm dep build/lint/template, negative controls, guard fail-closed tests, per-env render matrix). It never sees the correctness lens's findings; divergence is signal — both are posted even when they agree.
- **single** — the one-lens flow (reviewer only). Use for the **trivial** tier or when you pass `single`.

Two entry points feed the reviewer:

| Entry point | Who opened the PR | Style + action mode |
| --- | --- | --- |
| **Automatic** (orchestrator) | one of our own sub-agents | **`parallax` + `fix`** — the reviewer may push fixes to our branch. |
| **Manual** (`parallax-review` skill) | an external author | **`parallax` + `review-only`** — comment-only; **never push** to someone else's branch, so the two branded reviews are the whole deliverable. |

Set `Style:` and `Mode:` explicitly in the dispatch prompt (below). For a `sensitive` PR, prefer a stronger reviewer model for the correctness lens when the runtime supports it.

## Dispatch prompt template

```markdown
Goal: Review and fix PR <url>
Context: <one-line summary of the original task>
Key files: <paths most relevant to the change>
Constraints: <what to preserve / not touch>
Tier: <standard | sensitive>   # sensitive → expect rendered proof + adversarial lens
Style: <parallax | single>     # parallax → two branded lenses (correctness + adversarial)
Mode: <fix | review-only>      # review-only (external PR) → comment-only, never push
Protocol: Triage tier, render proof at merge-base for chart/values PRs, run the correctness pass,
  dispatch the independent adversarial (Codex) lens for parallax, fix blocking issues (fix mode only),
  reply to AND resolve every bot thread, check CI, iterate at most 2 times, post the two branded
  lenses (parallax), then hand off to human.
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
4. Reply once per bot finding using the categories below, citing fix commits or specific technical evidence — then **resolve the thread** (bot resolve command, or the host's `resolveReviewThread` API) so the PR hands off with zero open bot threads. Only resolve a finding you actually addressed.

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

**Tier**: <trivial | standard | sensitive>

### What was reviewed
- <areas>

### Bot reviews ingested
- <bot>: <posted N findings | timed out | not present>

### Direct replies posted to bots
- <bot>: <fixed M | acknowledged K | disagreed L | out-of-scope J> · threads resolved <R>/<total>

### Rendered proof (chart/values PRs)
- <chart @ env, merge-base→HEAD, N manifests changed, control empty | N/A>

### Cross-model verify (sensitive tier)
- <per blocking finding: confirmed / refuted / split | N/A>

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

### Parallax output shape (parallax style)

In parallax style the reviewer posts **two separately-branded reviews** in addition to (or, in `review-only`, in place of) the summary above. Each carries a stable HTML marker for later tooling:

```markdown
<!-- parallax:correctness -->
## 🔍 Parallax · correctness lens (Claude)
**Verdict:** <N/N offline checks pass | M blocking issue(s) found>
- Rendered proof: <chart @ env, merge-base→HEAD, N manifests changed, negative control empty | N/A>
- Claims verified / bot findings adjudicated / blocking / non-blocking
```

```markdown
<!-- parallax:adversarial -->
## 🧨 Parallax · adversarial lens (Codex)
**Verdict:** <no required change found after reproduction | required change: …>
<Codex's reproduced evidence + break-attempts, verbatim>
```

The adversarial lens is posted **verbatim** from the Codex run — never softened or re-rationalized. If the two lenses disagree, the split is surfaced for the human to adjudicate, never silently reconciled.
