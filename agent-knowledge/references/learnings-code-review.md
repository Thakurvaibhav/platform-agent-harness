# Learnings: Code Review

Patterns, gotchas, and best practices for PR review workflows.

## Entries

1. **Known review bots post asynchronously.** Wait for bot reviews (CodeRabbit, Cursor Bugbot) before starting your own pass — they may take several minutes. Poll with a timeout rather than blocking indefinitely.

2. **Reply to every bot finding explicitly.** Silent ignoring creates ambiguity for human reviewers. Classify each finding as fixed, acknowledged, disagreed, or out-of-scope.

3. **Bot false positives are common for YAML-only PRs.** Security scanners and code-quality bots may flag values files, namespace labels, or config-only changes that have no real risk. Document these patterns so future reviewers don't waste time re-evaluating.

4. **CI check context matters.** A passing CI run on a values-only PR may not exercise the actual Helm rendering. Verify with `helm template` locally when CI only runs linting.

5. **Cap fix iterations at 2.** After two rounds of fixes, document remaining issues and hand off to a human. Unbounded iteration loops waste tokens and rarely converge on non-trivial disagreements.
