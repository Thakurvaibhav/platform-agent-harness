---
name: parallax-review
description: >-
  Run a Parallax review on a PR — two independent model lenses (🔍 Claude
  correctness + 🧨 Codex adversarial) posted as two branded GitHub reviews.
  Use when the user says "parallax review <url>", "parallax-review", "run the
  two-lens review on this PR", or points at a PR (usually authored by someone
  else) and asks for the deeper cross-model review. For PRs our own agents just
  created, the orchestrator already auto-dispatches parallax — this skill is the
  manual entry point, mainly for external PRs.
---

# Parallax Review

Dispatches the [`pr-reviewer`](../../core/agents/pr-reviewer.md) sub-agent in
**Parallax** mode: it runs its own 🔍 correctness lens (Claude) and dispatches an
independent 🧨 adversarial lens (Codex, via
[`agent-knowledge/scripts/codex-dispatch.sh`](../../agent-knowledge/scripts/codex-dispatch.sh))
that tries to *break* head against the PR's claims in a read-only worktree at the
merge-base, then posts **two separately-branded GitHub reviews**.

This skill is a thin orchestrator — it only picks the action mode and tier and
dispatches. The full procedure lives in
[`core/agents/pr-reviewer.md`](../../core/agents/pr-reviewer.md) (Operating modes,
Step 3.5, Step 7.5) and the dispatch matrix in
[`core/protocols/pr-review-loop.md`](../../core/protocols/pr-review-loop.md).

## When to use

- The user asks for a "parallax review" / "two-lens review" / "cross-model review" of a PR.
- A PR (usually authored by someone else) needs the deeper adversarial pass, not just a single-lens read.
- Our own agents' PRs are already auto-dispatched to parallax by the orchestrator — reach for this skill mainly for **external** PRs, or to re-run parallax on our PR explicitly.

## What to do

1. **Capture the input:** a PR URL (or `owner/repo#N`). If none was given, ask for one.

2. **Decide the action mode:**
   - **External PR (someone else's branch)** → `Mode: review-only` (comment-only, never push). This is the common case for this skill.
   - **Our own PR** → `Mode: fix` (the reviewer may push fixes). Usually the orchestrator already auto-dispatched parallax on our PRs, so only use `fix` here if explicitly re-running.

3. **Pick the tier** (the reviewer self-triages too): `sensitive` for RBAC/secrets/NetworkPolicy/production-cluster/CRD/auth-ingress-filter config; else `standard`. For a `sensitive` PR, request a stronger model for the correctness lens at dispatch when the runtime supports it.

4. **Dispatch `pr-reviewer`** with the dispatch-prompt template from
   [`core/protocols/pr-review-loop.md`](../../core/protocols/pr-review-loop.md), setting:
   - `Style: parallax`
   - `Mode: review-only` (external) or `fix` (ours)
   - `Tier: <standard | sensitive>`
   - the PR URL, a one-line context, and any constraints the user gave.

5. **Relay the outcome:** confirm both lenses posted (🔍 correctness + 🧨 adversarial), surface the two verdicts, and **flag any disagreement between the lenses** for the human to adjudicate — never reconcile it silently.

## Notes

- The two lenses are **independent** — the Codex prompt never receives the Claude findings, and the correctness pass runs before its output is read. Divergence is signal; both are posted even when they agree.
- Read-only by construction: the adversarial lens works in an isolated worktree at the merge-base and never mutates. In `review-only` mode nothing is pushed at all.
- Cost: two model runs per PR. Fine for sensitive/standard; for a trivial PR prefer a single-lens review.
