---
name: shiny-engineer
description: >-
  Structured engineering workflow with iterative refinement. Implements the
  "shiny" formula (Design, Implement, Review, Test, Submit) combined with the
  rule-of-five expansion (Draft, Correctness, Clarity, Edge Cases, Excellence)
  on the implementation step. Use when building a feature, fixing a non-trivial
  bug, or doing any engineering work that spans multiple files or involves
  architectural decisions. Do NOT use for one-line fixes, exploratory research,
  or tasks the user explicitly wants done fast without ceremony.
---

# Shiny Engineer

Most engineering work goes wrong the same way: a draft solution gets shipped before it has been pressure-tested. This skill is a deliberate, multi-pass workflow that surfaces problems early and makes them cheap to fix.

Use this when **quality matters**. Skip it for trivial edits.

## When to use

- Building a new feature.
- Fixing a non-trivial bug.
- Refactoring across multiple files.
- Anything where the first implementation is unlikely to be the right one.

## When NOT to use

- One-line fixes.
- Pure research / investigation tasks.
- Exploratory prototyping.
- Tasks the user explicitly says to do fast without ceremony.
- Tasks already covered by a specialist sub-agent's own pre-completion checklist (`helm-engineer`, `argocd-engineer`, etc. already encode their version of this). Use this directly only when no specialist matches.

## The formula

Five passes. Each pass has a single concern. Do them in order.

### 1. Design

Before any code:

- State the goal in one sentence.
- List the inputs (files, APIs, constraints, prior art).
- Identify the smallest reasonable scope.
- Search the repo for existing utilities, patterns, helpers. **Reuse-first** ([`core/protocols/safety-and-handoff.md`](../../core/protocols/safety-and-handoff.md)) — extend what's there, don't fork.
- Decide the structure: which files change, which functions land where, what gets tested.

Output: a 3–8 line design comment in the bd task (or your scratch note) the user can sanity-check before you start.

### 2. Implement (rule-of-five expansion)

Implementation is not one pass — it's five sub-passes on the same code.

**2a. Draft.** Write the most obvious working version. Don't optimise. Don't over-comment. Get to "it runs."

**2b. Correctness.** Re-read the draft against the goal. Walk every code path. For each branch ask: "if input X arrives here, does this produce the right output?" Fix bugs immediately.

**2c. Clarity.** Rename ambiguous identifiers. Split long functions. Inline noise. Add a comment ONLY where the *why* is non-obvious (a constraint, a workaround, a surprise). Default to no comments — self-documenting code is the goal.

**2d. Edge cases.** Enumerate boundaries: nil, empty, zero, max, malformed, racing, timed out, partial. For each, ask "what happens?" Handle the ones that matter; explicitly document the ones you're choosing not to handle.

**2e. Excellence.** Step back. Read the diff as if you were reviewing it. What still feels wrong? Tighten. This is the polish pass. It usually moves five to ten lines and removes ten more.

### 3. Review

Open the diff. Apply [`core/protocols/pr-review-loop.md`](../../core/protocols/pr-review-loop.md) Step 3 categories to your own work:

1. Correctness.
2. Security.
3. Reuse and duplication.
4. Repo conventions.
5. Edge cases.
6. Completeness.

Fix every blocking issue. Note non-blocking ones for the PR description.

### 4. Test

- Run the appropriate validation (`helm dep build && helm lint && helm template`, `pytest`, `go test`, lint, etc.).
- Run any pre-completion checklist from your specialist sub-agent or [`core/protocols/bd-and-memory.md`](../../core/protocols/bd-and-memory.md).
- Capture evidence: command + pass/fail + one-line summary. The PR body needs this.

### 5. Submit

Use the [`create-pr` skill](../create-pr/SKILL.md). The PR body includes:

- **Why** (one paragraph).
- **What changed** (bulleted, file-level).
- **Validation** (evidence rows).
- **Risk** (low / medium / high + smallest unit that could regress).

After submit:

- Follow CI with `gh pr checks <num>`.
- Decide whether to dispatch [`pr-reviewer`](../../core/agents/pr-reviewer.md) per the [PR review loop matrix](../../core/protocols/pr-review-loop.md).
- Persist any non-obvious learning via `bd remember` and fill the `## Knowledge updates` section of your handoff.

## Why this works

The cost of fixing a bug grows roughly 10x every time it crosses a stage boundary (in your head → on disk → in the PR → in CI → in prod). Each pass in the formula moves work earlier in that chain. The same hour spent applying the formula saves multiple hours of review back-and-forth, CI iteration, and post-merge fix-ups.

## Common rationalizations to reject

| "Why I want to skip a pass" | Why you shouldn't |
| --- | --- |
| "The code is simple, it doesn't need clarity pass" | Future-you reads ambiguous code too. 30 seconds now saves five minutes later. |
| "Edge cases never happen in practice" | They happen. The cost ratio is asymmetric — handle them now or page someone at 3 AM. |
| "Reviewer will catch issues anyway" | The reviewer's job is the second pass, not the first. Send something already worth reviewing. |
| "Excellence pass feels like polishing for its own sake" | Polish removes lines. Smaller diffs ship faster and break less. |

## Output expectations

When you use this skill, the visible artifacts at the end are:

- A clean PR with structured body.
- All validation evidence in the PR body.
- A `bd remember` entry for any non-trivial learning.
- A handoff report (if dispatched) with the mandatory `## Knowledge updates` section filled in.
