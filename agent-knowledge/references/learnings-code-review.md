# Learnings: Code Review

Patterns, gotchas, and best practices for PR review workflows.

See also: `learnings-progressive-delivery.md`, `learnings-agent-workflow.md`, `learnings-confluence.md`, `learnings-envoy-gateway.md`

## Entries

1. **Known review bots post asynchronously.** Wait for bot reviews (CodeRabbit, Cursor Bugbot) before starting your own pass — they may take several minutes. Poll with a timeout rather than blocking indefinitely.

2. **Reply to every bot finding explicitly.** Silent ignoring creates ambiguity for human reviewers. Classify each finding as fixed, acknowledged, disagreed, or out-of-scope.

3. **Bot false positives are common for YAML-only PRs.** Security scanners and code-quality bots may flag values files, namespace labels, or config-only changes that have no real risk. Document these patterns so future reviewers don't waste time re-evaluating.

4. **CI check context matters.** A passing CI run on a values-only PR may not exercise the actual Helm rendering. Verify with `helm template` locally when CI only runs linting.

5. **Cap fix iterations at 2.** After two rounds of fixes, document remaining issues and hand off to a human. Unbounded iteration loops waste tokens and rarely converge on non-trivial disagreements.

6. **A bot can be "done" without a new comment.** Some reviewers (e.g. CodeRabbit) update their existing "review in progress" comment in place — the comment count never increments and the reviews list stays empty; detect completion by a marker in the comment **body**. Cursor Bugbot's authoritative commit is its footer (`Reviewed … for commit <SHA>`), not the visible `diff_hunk` — if that SHA is not current `HEAD`, it scanned a stale commit and its findings may already be fixed. Verify against `HEAD` before acting.

7. **Reply *and* resolve.** A threaded reply alone leaves a bot finding open. Drive each to resolved — a bot resolve command (`@coderabbitai resolve`) or the host's `resolveReviewThread` GraphQL mutation for bots that do not self-resolve. Only resolve a thread you actually addressed (fixed / disagreed-with-reason / acknowledged). Target zero open bot threads at hand-off.

8. **Rendered proof beats source-diff reading.** For Helm/values PRs, render the chart at the `git merge-base` and at `HEAD`, then diff the *manifests* — a values change can be inert (disabled component, wrong key, deep-merge override) or blast wider than the source implies. Always include a **negative control** (an untouched chart whose rendered diff must be empty) to prove the render harness actually surfaces changes. Source changed but rendered diff empty = a blocking finding, not a pass.

9. **Cross-model verify high-blast findings.** On sensitive PRs (RBAC, secrets, production manifests), do not assert a blocking finding — or a clean verdict — on one model's judgment. Dispatch a different model/runtime to *refute* each blocking finding (default-to-refuted); keep only what survives, and surface splits to the human rather than silently picking a side.

10. **Anchor behavior-preservation proofs at the `git merge-base`, not the immediate parent.** With multiple commits, the parent only proves the last commit is conservative; earlier commits in the PR may have widened scope. `git merge-base origin/main <tip>` is the true baseline for render-diff and before/after proofs.
