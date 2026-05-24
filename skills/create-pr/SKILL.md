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

## Steps

```bash
# Verify branch
test "$(git rev-parse --abbrev-ref HEAD)" != "main" || { echo "refuse: on main"; exit 1; }
test "$(git rev-parse --abbrev-ref HEAD)" != "master" || { echo "refuse: on master"; exit 1; }

# Ensure latest
git fetch origin main
git rebase origin/main || { echo "resolve rebase conflicts and re-run"; exit 1; }

# Push the feature branch (set upstream on first push)
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"

# Create the PR
gh pr create \
  --title "<conventional commit style title>" \
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

## Memory

Before finishing:

```bash
bd remember "<self-contained insight about the change>" --key <repo>/<prefix>/<topic>
```
