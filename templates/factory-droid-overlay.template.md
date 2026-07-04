# Factory Droid Global Instructions (Overlay)

**Single source of truth:** Read `~/.factory/droids/references/shared-protocols-core.md`
(or `agent-knowledge/references/shared-protocols-core.md`) at session start. This
overlay adds ONLY Factory Droid-specific mechanics.

# Startup

At session start or resume, follow the **Droid Startup Checklist** in the shared
protocols. If `<repo>/graphify-out/graph.json` exists, load it for architecture
questions.

**Drift check (every session start/resume):** Run
`agent-knowledge/scripts/drift-check.sh`. Surface warnings as a brief status line
before starting task work. Do not auto-fix without approval.

# Agent Delegation Policy

**ALWAYS delegate to a specialist sub-agent when one exists for the task.** Do not
perform the work yourself if a matching droid is available.

The main session should make the delegation decision proactively. The user should
not need to prefix requests with "dispatch the relevant subagent" for normal work.
If a task clearly maps to a specialist or benefits from parallel research, dispatch
immediately after gathering minimal context for a precise prompt.

## Routing table

| Task domain | Specialist droid |
|-------------|-----------------|
| Tool research, version assessment, production readiness | `tool-researcher` |
| Helm chart creation/modification | `helm-engineer` |
| ArgoCD manifest creation/enablement | `argocd-engineer` |
| CI workflows, alerts, dashboards, observability | `platform-engineer` |
| Project planning, task breakdown, ticket updates | `task-planner` |
| Parallel code exploration, research, Q&A | `general-engineer` |
| Post-PR review, fix, and CI feedback handling | `pr-reviewer` |

## When to work directly

1. No sub-agent matches (ad-hoc validation, quick comment, Slack draft).
2. The task is trivial (< 2 minutes, single file read/edit).
3. A sub-agent has already failed or timed out on the same task.

## Multi-droid chains

When a task spans multiple droids (e.g., new tool = tool-researcher ->
helm-engineer -> argocd-engineer -> platform-engineer), the
orchestrator self-orchestrates the chain. Dispatch sequentially, passing each
droid's output as context to the next. Do NOT dispatch task-planner for
orchestration.

## When a droid fails or times out

1. Read the error. Identify: prompt issue, tooling issue, or genuine blocker.
2. Retry ONCE with tighter prompt -- add the missing context or constraint.
3. If fails again, break into smaller pieces and dispatch separately.
4. If still blocked, perform the work directly.
5. **Post-failure retrospective (mandatory after step 4):**
   - Diagnose: (a) prompt too vague, (b) missing context, (c) tooling limit, (d) genuine complexity?
   - Ingest the fix into `learnings-agent-workflow.md`.
   - If same droid + same failure mode recurred, flag for droid config update.
   - `bd remember "<droid> fails on <pattern> because <root cause>. Fix: <what worked>" --key <domain>/lesson/<topic>`

## Dispatch prompt structure

- Put the TARGET architecture/model FIRST, before "explore the repo."
- State the deployment model explicitly at top for tool-researcher.
- For file/directory deletion: handle from main session (`git rm -r`).
- **Every dispatch must include verification criteria.** End with "Verify by:" section.
- Include this standard preamble in every dispatch:
  > Read shared-protocols-core.md for shared protocols. Read index.md to discover
  > available docs and learnings. Run knowledge-search.sh <keywords> for prior art.
  > Prefix read-only shell with rtk. Never prefix mutating or piped commands.
  > Before finishing, persist non-obvious findings via bd remember.

# Knowledge Consolidation

On every session start or resume:
1. Check the `<repo>/meta/last-consolidation` memory.
2. If missing or older than 7 days, ask: "Last consolidation was N days ago. Want me to run `/consolidate`?"
3. On approval, dispatch `general-engineer` with the consolidation workflow.

Do NOT auto-run without user approval.

# Token Optimization (rtk)

`rtk` is at `/opt/homebrew/bin/rtk`. Before every Execute call, decide: native tool
(Read/Grep/Glob/LS), prefix with `rtk`, or run raw. Default to `rtk` for read-only
verbose commands.

Quick reference -- always prefix: `rtk git status/diff/log/show/branch`,
`rtk gh pr view/list/checks`, `rtk kubectl get/describe/logs`,
`rtk helm template/lint`. Never prefix: mutating commands, piped/chained, bd commands.

# Skill Activation Hints

| User says / context includes | Skill |
|------------------------------|-------|
| "review this PR", "find bugs in these changes" | `review` |
| "create a PR", "open a pull request" | `create-pr` |
| "debug this pod / CrashLoopBackOff / OOMKilled" | `k8s-debug` |
| "upgrade the helm chart", "bump appVersion" | `helm-upgrade` |
| "build a feature", "fix this bug" (non-trivial) | `shiny-engineer` |
| "clean up this code", "refactor for reuse" | `simplify` |

Skill vs droid precedence: for domain work (Helm, ArgoCD, CI), delegate to the
specialist droid. Only activate skills directly for ad-hoc work in the main session.

# PR Review Dispatch Rules

After any droid returns a PR URL, evaluate whether to dispatch `pr-reviewer`
(different model for fresh perspective).

**ALWAYS dispatch for:**
- Helm chart changes
- ArgoCD manifest changes
- CI/alerting/observability changes
- Any PR touching >5 files or >100 lines
- Security-sensitive paths (secrets, RBAC, network policies)

**NEVER dispatch for:**
- Docs-only PRs
- Single-file config changes (<10 lines)
- User explicitly says "skip review"

**Dispatch template:**
```
Goal: Review and fix PR <url>
Context: <one-line summary>
Key files: <paths>
Constraints: <any constraints>
Protocol: Review diff, fix blocking issues, check CI, iterate max 2 times, hand off.
Persist non-obvious findings: bd remember "<insight>" --key <domain>/<category>/<topic>
```
