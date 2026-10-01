---
name: create-pr
description: >-
  Create a GitHub pull request for the current branch with a consistent
  description, ticket linkage, and CI follow-through. Use whenever the user
  wants to open a PR, submit a pull request, or push and create a PR.
---

# Create PR

This skill replaces ad-hoc `git push && gh pr create` invocations with a consistent flow that:

- Validates the branch and working tree.
- Generates a structured PR description with rationale (WHY, not just WHAT).
- Links the relevant external ticket.
- Triggers CI follow-through with `gh pr checks`.

## Preconditions

- Working tree clean (or staged changes deliberate).
- On a feature branch (never `main` / `master`).
- An external ticket ID is available in the calling task or in the bd task description.
- `gh` is authenticated.

## Resolve the base branch first — never assume `main`

Repo defaults genuinely differ (`main`, `master`, `dev`, `trunk`), and two repos side by side in
one estate routinely disagree. An ahead-check, a rebase, or a discipline gate run against the wrong
base compares the branch to something it never forked from: it reports a clean diff and the skill
reads as passing. Resolve it explicitly, in this order, and **fail loudly rather than fall back to a
guess** — re-derive it from `gh pr view --json baseRefName` whenever a PR already exists rather than
trusting a value written down earlier [learnings-code-review.md#34].

```bash
# 1. If a PR already exists for this branch, its own base is authoritative.
BASE_REF=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null)
# 2. Otherwise the remote's default branch.
[ -n "$BASE_REF" ] || BASE_REF=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
# 3. No silent default. Say what to run.
[ -n "$BASE_REF" ] || {
  echo "refuse: cannot resolve the base branch. Run 'git remote set-head origin -a', or pass the base explicitly."
  exit 1; }
```

Everything below uses `$BASE_REF`. Where a gate script resolves the base itself, let it — do not
pass a ref you computed here, and never a hard-coded one.

## Steps

```bash
# Verify branch
test "$(git rev-parse --abbrev-ref HEAD)" != "main" || { echo "refuse: on main"; exit 1; }
test "$(git rev-parse --abbrev-ref HEAD)" != "master" || { echo "refuse: on master"; exit 1; }

# Ensure latest, against the resolved base (see above)
git fetch origin "$BASE_REF"
git rebase "origin/$BASE_REF" || { echo "resolve rebase conflicts and re-run"; exit 1; }

# Confirm there is something to open a PR for — empty output means stop, not proceed
git log "origin/$BASE_REF"..HEAD --oneline

# Discipline gates — BLOCKING, both run before the branch is pushed.
# Mechanical, not advisory: do not substitute your own judgment for either.
# Omit --base on purpose: each script resolves the REMOTE default branch itself, which
# stays correct in a repo whose default is not `main` and cannot go stale the way a
# local ref does. Pass --base only to override a resolution you know to be wrong.
core/hooks/generic/comment-discipline.sh || {
  echo "refuse: fix the comments and amend, then re-run"; exit 1; }
core/hooks/generic/test-discipline.sh || {
  echo "refuse: cut the tests or name the contract each pins, then re-run"; exit 1; }

# Push the feature branch (set upstream on first push)
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

# Create the PR — see "PR title" below for the title rule
gh pr create \
  --base "$BASE_REF" \
  --title "<type>(<scope>): <description> (<TICKET-KEY>)" \
  --body "$(cat <<EOF
## Why

<one paragraph: motivation, what this unblocks, what it does NOT do>

## What changed

- <bulleted list of substantive changes>

## Validation

- <command/check>: <pass/fail evidence>

## Ticket

- <TICKET-KEY>: <ticket URL>

## Risk

- <one line: low / medium / high and the smallest unit that could regress>

EOF
)"

# Follow CI
pr_number="$(gh pr view --json number -q .number)"
gh pr checks "$pr_number"
```

## PR title

**Canonical rule: *PR titles* in [`core/protocols/bd-and-memory.md`](../../core/protocols/bd-and-memory.md).**
That file is the source of truth — sub-agents cannot invoke skills, so the protocol is the rule's
only reachable home for them. Restated here because this skill is the main path; if the two ever
read differently, the protocol wins.

Every PR title is Conventional Commits **and** carries its ticket key:

```
<type>(<scope>): <description> (<TICKET-KEY>)
```

```
chore(infra): remove the retired pool-2 node pool (PLAT-142)
feat(monitoring): add node-pool saturation alerts (OBS-77)
```

- **Type** from `feat|fix|chore|refactor|docs|test|ci|perf|build`. Pick one you can defend: a cost or noise reduction is `chore`; a behaviour correction is `fix`.
- **Scope is optional but single. Never comma-separate** — a title lint using [`amannn/action-semantic-pull-request`](https://github.com/amannn/action-semantic-pull-request) rejects `feat(a,b): …` outright. Multiple areas → pick the primary scope, or drop the scope.
- **Ticket key in trailing parens, UPPERCASE.** Branches read `feature/plat-142-slug`, so uppercase what you extract from one. If there is genuinely no ticket, omit it — **never invent one**.
- **The head commit's subject must match the PR title**, so a squash merge cannot produce a message that disagrees with the PR.
- Repo history is mostly *not* in this form. Do not copy it. The one exception is a repo with an enforced different convention (a title-lint CI job, or a `<type>: <TICKET-KEY> | <title>` house style) — follow the enforced one and say which you used.

## After the PR opens

1. If CI fails, read the failure (`gh pr checks <num>` plus the failing job's output), fix root causes (not symptoms), commit, push.
2. Add a `bd comments` entry referencing the PR.
3. If the original task is in `bd`, close it on merge: `bd close <id> --reason "PR #<num> merged."`.
4. Run [`core/protocols/pr-review-loop.md`](../../core/protocols/pr-review-loop.md) decision matrix — dispatch `pr-reviewer` if the change qualifies.

## Constraints

- Never push to `main` / `master`.
- Never `--force` to a protected branch; use `--force-with-lease` on your own feature branch only.
- Never auto-merge — humans review.
- Never include credentials, tokens, or real internal URLs in the PR body.
- Never hard-code a base branch. Resolve it, or let the gate script resolve it.

## Memory

Before finishing:

```bash
bd remember "<self-contained insight about the change>" --key <repo>/<prefix>/<topic>
```
