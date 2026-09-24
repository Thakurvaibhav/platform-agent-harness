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

## Agent attribution: 🤖 sign-off

**Anything an agent authors and posts under the user's identity ends with 🤖 on its own last line.** Not inline, not buried in a footnote — the last line.

Covers **chat** (Slack/Teams messages, drafts, thread replies, canvases) and **code review** (review comments, review bodies, replies to bot threads, issue comments, upstream issues). Applies to drafts handed up for approval exactly as to messages sent directly — users forward drafts as-is.

**Commit messages and PR descriptions are excluded** where the runtime already stamps them (`Co-Authored-By`, a generated-by footer). Double-marking adds noise, not signal. If your runtime stamps nothing, add the sign-off there too.

Anything posted goes out under the *user's* account and reads as written by them. That ambiguity costs the user, not the agent: a wrong or blunt review reads as their considered opinion, and an agreement reads as human review that never happened. It is worst on someone else's PR, where it spends their credibility with a colleague.

**If something already went out unmarked, edit it in** rather than leaving the record inconsistent:

```bash
gh api -X PATCH repos/<org>/<repo>/issues/comments/<id> -f body="<original>

🤖"
```

Never strip it because a message reads cleaner without it. A user may waive it for a specific message — that is their call; say what you are doing and do it.

## Altitude and voice

Applies to everything an agent writes for a human — handoff reports, PR bodies, review comments, design docs, chat messages. Write as the engineer **accountable for the decision**, for a reader who was not in the room and arrives six months late.

- **Lead with the decision and its consequence.** The exploration that got you there goes below it, or nowhere.
- **Name the tradeoff and what you rejected**, one line each. A decision without its discarded alternative gets re-litigated by the next person.
- **Label confidence** — verified (name the check), inferred (name the source), or assumed. Never let inferred read as verified. This is the same rule the Assumptions section of [`code-quality.md`](code-quality.md) applies to code, carried into shipped text.
- **Scope claims to what you actually checked** — "verified on dev; staging unobserved", not "verified".
- **Own an error in one line and move on.** State what was wrong and what is true now. No grovelling, no re-explaining the original reasoning.
- **No victory laps.** Do not narrate having been right, and credit whoever or whatever produced a finding.
- **Critique the artifact, never the author.** Assume the prior decision had a reason you cannot see; ask what it was before calling it wrong (see *Changing what you did not build* in [`code-quality.md`](code-quality.md)).
- **Drop "obviously", "simply", "just".** They tell a stuck reader the problem was beneath explanation.

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

## Code quality & comments

Reuse-first, comment discipline, and all other coding standards are canonical in [`code-quality.md`](code-quality.md) — not restated here.
