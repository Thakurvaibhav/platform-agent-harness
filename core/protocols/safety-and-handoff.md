# Safety, Constraints, and Handoff

Operating rules every sub-agent must apply, and the structured handoff format every delegated task ends with.

## Git safety

- **NEVER push directly to `main` or `master`.** Always use a feature branch.
- **NEVER `git push --force` on `main` / `master`.** Runtime denylists typically block this — don't try.
- Use `--force-with-lease` (not `--force`) when force-pushing your own feature branches.
- Use `git rm -r` for directory deletion in agent sessions. `rm -rf` is typically blocked by runtime risk gates.

## Kubernetes safety

- **NEVER mutate k8s resources.** No `kubectl apply|create|delete|patch|replace|edit|scale|rollout|set|annotate|label|taint|cordon|uncordon|drain`.
- **NEVER use Helm mutating verbs.** No `helm install|upgrade|uninstall|rollback`.
- Read-only is fine: `kubectl get|describe|logs|top`, `helm template|lint|show values`.

## File and repo safety

- Treat untracked files as user-owned. Never delete, overwrite, move, or `git clean` untracked files unless the user explicitly asked for those exact files.
- Before destructive file operations, inspect `git status --porcelain` to understand whether untracked files may be affected.
- Stop and ask before any cleanup operation that could remove untracked content.

## Secrets and public sharing

- Never commit credentials, API keys, tokens, real cluster names, real customer names, real internal URLs.
- Before any commit that changes examples, references, or templates, run [`sanitization/prepublish-checklist.md`](../../sanitization/prepublish-checklist.md): `trufflehog`, `gitleaks`, the local denylist, formatting check.
- Synthetic placeholders in public examples: `<company>`, `<cluster>`, `<env-cluster>`, `<namespace>`, `<service>`, `<TICKET-KEY>`.

## Handoff contract

Every delegated task ends with a structured report to the caller (parent sub-agent or main session). Use this exact format so chained delegation (`task-planner` → specialist → `general-engineer`) can be parsed reliably.

```markdown
## Summary
<1–3 sentences: what was done and the outcome>

## Changes
- <file/path/or/resource>: <what changed and why>
(one bullet per change; omit this section entirely for explicit read-only tasks)

## Verification
- <check name>: <pass | fail | skipped> — <evidence/command output/link>
(helm lint, yamlfmt, PromQL validation, pod logs clean, etc.)

## Artifacts
- bd task: <id> — <status>
- PR: <#num> — <url> (if applicable)
- Ticket: <key> (if applicable)

## Open questions / follow-ups
- <anything the caller must decide, unresolved bugs, out-of-scope issues filed as new bd tasks>
(use "None." if nothing)
```

### Rules

- Omit `## Changes` only for explicitly read-only tasks (research, investigation, validation).
- Every `Verification` bullet must be backed by a command or link — never claim "verified" without evidence.
- If a verification step failed, you must still report back. Do not silently retry or mask failures.
- If the task cannot be completed, replace `## Changes` with `## Blockers` explaining what's missing and exit before making PRs.

## Reuse-first rule

**Before writing any new function, utility, or pattern — search the codebase for an existing one.**

This applies to every sub-agent.

1. **Search first**: grep for keywords from the task in `utils/`, `helpers/`, `common/`, `shared/`, `lib/` and across the repo. Check function names, class names, comments.
2. **Reuse or extend**: if something similar exists, use it. If it's close but not exact, extend it — don't fork a parallel implementation.
3. **Document if new**: if nothing exists, place it where future code can find it (shared module, not buried in a feature directory).

Blocking violations (must be fixed before completing any task):

- Creating a function that duplicates >80% of an existing one.
- Reimplementing a utility that already lives in a shared module.
- Ignoring existing naming conventions, error handling, or config approaches.

Common rationalizations to reject:

| Excuse | Response |
| --- | --- |
| "My version is slightly different" | Extend the existing function. Don't duplicate and diverge. |
| "The existing code is messy" | Refactor it in a separate task. Don't create a parallel version. |
| "It's faster to rewrite" | Rewriting is faster today. Maintaining two versions is slower forever. |
