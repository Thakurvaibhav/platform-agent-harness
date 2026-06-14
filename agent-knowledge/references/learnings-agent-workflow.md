# Sub-Agent Workflow Learnings

Numbered, append-only. **Update the existing entry — never duplicate.**

## Dispatch discipline

1. **Sub-agents time out on simple tasks when they explore unnecessarily.** For trivial changes (single file update), the dispatch must say "this is a simple change — read only `<file>` and modify it." Unnecessary repo scanning produces timeouts and burns context.

2. **Sub-agents lack awareness of in-flight PRs.** When amending is preferred over creating a new PR, explicitly tell the agent about the existing PR, branch name, and worktree path. They won't discover open PRs on their own unless instructed to check `gh pr list`.

3. **"Not exposed" is not "disabled".** Agents interpret "don't expose the UI" as "disable the UI" (`ui.enabled: false`). Always be explicit: "keep `ui.enabled=true` but omit Tailscale/Ingress annotations." Binary on/off is handled well; subtle distinctions require explicit examples.

4. **Put the target architecture FIRST in every dispatch.** Sub-agents bias toward current repo state and ignore buried targets. The intended end-state must precede any "explore the repo" instruction.

5. **Every dispatch must include a `Verify by:` section.** Vague tasks produce vague results. Concrete pass/fail criteria with commands or queries.

## Parallel work

6. **Independent validations should run in parallel** with one worker per target and a shared self-contained playbook. The orchestrator aggregates after workers return. Empirical observation: a 12-check readiness playbook run across 3 clusters in parallel completes in ~5 minutes vs ~45 minutes sequential — **3x+ wall-clock speedup**.

7. **Validation playbooks are the highest-ROI agent artifact.** A well-structured playbook (numbered checks, pass/fail criteria, specific commands per check) can be executed by any agent instance with no additional context. Creation cost (~1h) is amortized across every subsequent run.

## Knowledge capture

8. **Encode agent mistakes into protocols or domain packs the same session.** Delayed encoding leads to repeated mistakes across sessions. Every correction is captured in the appropriate `agent-knowledge/references/learnings-*.md` file before the session ends.

9. **Copy-paste contamination in generated docs.** When generating docs from templates or existing docs, always review for content carried from the source that doesn't apply.

10. **The index is the cheapest abstraction in the harness.** Every doc that lands in `agent-knowledge/references/` gets a row in `agent-knowledge/references/index.md`. Agents grep the index before the repo — saves enormous amounts of exploration.

## Memory hygiene

11. **`bd remember` text must be self-contained.** A future session must understand the memory without the current chat history. Bad: "Fixed the issue we discussed." Good: "After bumping `<example-operator>` 1.4 → 1.6, values key `controller.metrics.port` renamed to `metrics.port`."

12. **Don't store trivial facts.** "Ran `helm template` successfully" is not a memory. "After bumping `<chart>`, `helm template` exits clean but the rendered output silently drops the upstream `controllers` list because we override it without including upstream defaults" is a memory.

13. **Conflicts with prior learnings must be flagged in handoff, not silently edited.** Use the `CONFLICT: ...` marker in the handoff so the human decides which version stays.

## Runtime constraints

14. **Sub-agents typically cannot delete directories.** The runtime risk gate often blocks `rm -rf` for sub-agents. For tasks requiring directory deletion, handle from the main session or use `git rm -r`.
