# Sub-Agent Workflow Learnings

See also: `learnings-code-review.md`, `learnings-fleet-campaigns.md`, `learnings-confluence.md`, `learnings-terraform.md`

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

8. **Main session should proactively dispatch.** Users should not need to say "dispatch the relevant subagent" for normal specialist work. The orchestrator should dispatch immediately when a task clearly maps to a specialist agent or benefits from parallel worker research, after gathering only enough context to write a precise prompt. Keep direct execution for trivial single-file/read-only tasks or when a prior subagent already failed.

## Knowledge capture

9. **Encode agent mistakes into protocols or domain packs the same session.** Delayed encoding leads to repeated mistakes across sessions. Every correction is captured in the appropriate `agent-knowledge/references/learnings-*.md` file before the session ends.

10. **Copy-paste contamination in generated docs.** When generating docs from templates or existing docs, always review for content carried from the source that doesn't apply.

11. **The index is the cheapest abstraction in the harness.** Every doc that lands in `agent-knowledge/references/` gets a row in `agent-knowledge/references/index.md`. Agents grep the index before the repo — saves enormous amounts of exploration.

## Recurring operations

12. **Playbook-driven recurring operations scale autonomously.** Write operational playbooks with specific queries (including datasource UIDs), pass/fail criteria, and fallback procedures. Any agent instance can execute with consistent results. Pattern: N parallel workers, M clusters, ~5 min wall time vs ~60+ min manual. Creation cost (~2h) amortized across 30+ runs = massive ROI.

13. **Autonomous error reclassification from accumulated run data.** When an agent executes the same health check repeatedly, it accumulates evidence that ad-hoc reviews miss. After 20+ consistent runs showing a metric scaling linearly with cluster size, the agent proposed splitting a category — a data-driven decision from run-over-run pattern recognition. Encourage agents to flag patterns across runs, not just report each run in isolation.

14. **Multi-surface consistency updates in single session.** When a classification or definition changes, update ALL surfaces in one session: playbook queries, dashboards, result templates, documentation, tickets, and memories. Partial updates leave stale surfaces that confuse future sessions. The orchestrator should maintain a checklist of all surfaces that reference the changed concept.

15. **Document CLI gotchas in playbooks, not tribal knowledge.** Silent-failure CLI behaviors (empty results from wrong time format, TAB characters in grep patterns, timeouts on large log volumes) are discovered once and forgotten. Document them as callout boxes directly in the playbook alongside the queries they affect.

16. **PRs from specialist sub-agents must include rendered/compiled output in the PR description.** When a sub-agent creates a PR that generates Kubernetes manifests, alert rules, or any templated output, the PR description MUST include the full rendered output in a collapsible `<details>` section. This enables reviewers to verify exact resources without checking out the branch.

17. **Playbook phase checks MUST be parallelized across sub-agents.** When running multi-check playbooks, dispatch parallel sub-agents grouped by tool dependency: (1) kubectl group, (2) PromQL/metrics group, (3) functional tests. Keep prompts SHORT and focused (one group per sub-agent, explicit commands, no exploration). Sub-agents timeout on long prompts — split by group.

18. **Validation run post-actions are implicit and mandatory.** After ANY playbook validation dispatch returns, the orchestrator MUST: (a) present results to user, (b) update the report file, (c) update the bd task with a summary comment, (d) update external tickets. Never wait for user to request these.

19. **Short checks run faster directly than via sub-agent.** For brief known-good-pattern checks (~5 commands), run directly from the main session rather than dispatching. Sub-agents timeout on large log volumes. Direct execution completes in ~20s. Reserve sub-agents for first-time runs where the longer prompt and file creation justify the overhead.

## Memory hygiene

20. **`bd remember` text must be self-contained.** A future session must understand the memory without the current chat history. Bad: "Fixed the issue we discussed." Good: "After bumping `<chart>` 1.4 → 1.6, values key `controller.metrics.port` renamed to `metrics.port`."

21. **Don't store trivial facts.** "Ran `helm template` successfully" is not a memory. "After bumping `<chart>`, `helm template` exits clean but the rendered output silently drops the upstream `controllers` list because we override it without including upstream defaults" is a memory.

22. **Conflicts with prior learnings must be flagged in handoff, not silently edited.** Use the `CONFLICT: ...` marker in the handoff so the human decides which version stays.

## Investigation and debugging

23. **Build an evidence chain before claiming authoritativeness.** When asserting data from point A represents truth at point B, prove the full chain: (a) no transformation between A and B, (b) processing order supports the claim, (c) no post-processing invalidates it, (d) production proof exists. A single "it should work" is not sufficient — any link in the chain could break the claim.

24. **Document WHY something failed, not just that it failed.** A failed capture attempt became the most valuable finding once the mechanism was traced. The explanation of WHY is more durable and reusable than the raw result. Always investigate failures to root cause.

25. **`kill 1` does not reliably terminate containers.** PID 1 in containers often has special signal handling (init process behavior). Many images ignore SIGTERM sent to PID 1. Use `killall <process-name>` instead. This applies to any ephemeral debug container cleanup.

26. **Capture at multiple points and explain discrepancies.** When investigating data flow, capture at both ends simultaneously. If one side shows data and the other doesn't, the discrepancy IS the finding — explaining the gap reveals architecture.

27. **Regression attribution — temporal baseline BEFORE mechanism.** When a new symptom appears AFTER any change, the FIRST causation test is "was this symptom already occurring before the change?" Range-query the metric across the pre-change boundary. If it predates the change, the change is exonerated. TRAP: a freshly-fired instance makes a chronic intermittent condition LOOK new — judge by HISTORY, not the latest instance's timestamp. Mechanism/path evidence is a valid but slower FALLBACK.

28. **Dispatch validation sub-agents by PLAYBOOK REFERENCE, not inline instructions.** Pass the playbook path and target identifier. Do NOT inline the 12+ check commands — inline prompts are brittle and verbose. The playbook is the single source of truth; agents pick up any playbook updates automatically.

29. **Agent fan-out cap: ~15 background sub-agents at once trips rate-limiting.** The safe concurrent fan-out cap is ~8-10. For larger fans, batch into waves: dispatch 8, wait for completion, dispatch next 8.

## Runtime constraints

30. **Sub-agents typically cannot delete directories.** The runtime risk gate often blocks `rm -rf` for sub-agents. For tasks requiring directory deletion, handle from the main session or use `git rm -r`.

31. **MCP tools that require parent-level (OAuth/host) context are NOT available in sub-agent context.** Sub-agents must PREPARE the content/payload and RETURN it to the parent, which makes the actual call. This applies to any MCP server requiring parent-level access (Confluence, Slack, etc.).

32. **`kubectl exec` into prod pods may be soft-blocked by auto-mode classifiers.** In-cluster connectivity checks via `kubectl exec` into production pods hit "Remote Shell" boundaries. Mitigations: (a) substitute PromQL connectivity evidence, (b) retry with explicit read-only-intent, (c) mark check NOT RUN and lean on prior clean runs, (d) prefer `wget`/`curl` from a dedicated echo-client pod.

## bd and scripting gotchas

33. **`bd close` can flap closes back to open — flush after every close.** `bd close` auto-imports `.beads/issues.jsonl` BEFORE each write, so closing task B reverts an earlier same-session close of task A. Symptom: closes report success but `bd show` flaps back to open. Fix: flush db after every single close with `bd export`. Verify authoritative state with `bd export`, not `bd show`.

34. **`set -euo pipefail` + heredoc: any check that must RECORD-and-CONTINUE on failure MUST be in an `if`-condition.** A standalone `python3 - <<PY ... PY; rc=$?; if [[ $rc ]]` aborts the WHOLE script before `rc=$?` runs. FIX: wrap as `if python3 ... ; then note_pass; else note_fail; fi` — the if-condition makes non-zero non-fatal under `set -e`.

## Cross-harness (multiple agent runtimes sharing one bd hive)

35. **The memory layer ports across runtimes IF the substrate is runtime-neutral.** The knowledge home (files), the bd hive, and `AGENTS.md` convention port for free. Three gotchas: (1) `BEADS_DB` must live in shell profile (`~/.zshrc`), NOT just one runtime's config, or the hive pin is invisible to other runtimes. (2) `AGENTS.md` must be SPLIT — neutral core + per-runtime overlay — because runtime-specific directives confuse other runtimes. (3) The learning-gate enforcement is runtime-hook-only; the runtime-neutral enforcement point is GIT HOOKS (post-commit), which fire regardless of which agent drove the commit.

36. **bd is backed by a running Dolt SQL daemon, NOT flat files.** `issues.jsonl` is just the git-sync export/import. A sandboxed worker may FAIL both directions: reads silently return 0 memories (can't reach daemon, falls back to empty), writes error "server unreachable." Root cause: sandbox blocks localhost TCP. Fix: enable network access for the sandbox and/or add `<repo>/.beads` to writable roots. Always smoke-test bd read-back before building any cross-runtime integration.

37. **Cross-runtime subagent parity via dispatch scripts.** Runtimes without native sub-agent types achieve parity via a dispatch script that wraps headless execution with a specialist role. Specialist role definitions are reusable across runtimes if they reference shared protocols (not runtime-specific features). Gotchas: (a) headless exec may refuse non-git dirs — pass a skip-git-check flag; (b) feed stdin from `/dev/null` or it hangs waiting for input; (c) session-start hooks must write valid JSON to stdout (plain text causes invalid-output errors); (d) hook trust systems may skip untrusted hooks headlessly — put enforcement in git hooks, not trust-gated hooks.

## Value of AI agents

38. **Calendar-time compression is the dominant value for design-intensive work.** When each design pivot manually = a full PR review cycle (1-2 days), agents running implement-review-fix-validate in minutes compress 4 pivots into one session (~3h). Work-hours ~5x; calendar ~8-10x. Repetitive enablement (per-target values) is ~4-5x work-hours with negligible calendar benefit.

39. **Pattern transfer eliminates design iteration on subsequent implementations.** First implementation: 4 design pivots, 4 review rounds, ~3h. Second implementation (same pattern): 0 pivots, 2 mechanical fixes, ~1.5h. Key: encode mistakes within the same session they occur.

40. **PR reviewer as quality gate pattern.** Dispatch a review sub-agent on every chart PR (~2 min cost). Fresh model perspective finds patterns the authoring agent missed. Always dispatch in parallel with description updates to save wall-clock time.

## Docs, reporting, and knowledge-base craft

41. **Chart generation on a stock Mac: system python3 has no matplotlib -- use ephemeral uv**: `uv run --with matplotlib python script.py` (resolves in ms, no venv). For executive/summary charts: matplotlib Agg backend, horizontal `barh` + log xscale when one value dwarfs others, value labels on bars, hide top/right spines.

42. **md to PDF with no pandoc/weasyprint (mac): render via headless Chrome**: (1) convert md to HTML with print CSS (`@page` size A4 margin; img max-width 100% + page-break-inside avoid). Write the .html INTO the same dir as the md so relative image paths resolve. (2) `Google Chrome --headless=new --no-pdf-header-footer --print-to-pdf=out.pdf file:///abs/path.html`.

43. **Learnings-KB cross-ref consistency method: ONE adjacency matrix, verified by edge-symmetry script.** Build a single matrix of genuine file-to-file neighbors, apply it identically to (a) each file's `See also:` header and (b) the index.md Cross-refs column, verify with a script asserting symmetry (A in B's refs iff B in A's). GOTCHA: regex `[a-z-]+` silently drops filenames containing digits (e.g. `learnings-k8s-sa.md`) -- use `[a-z0-9-]+`.

44. **KB dedup is mainly merging cross-file duplicate claims, not rewriting.** Pick ONE canonical home (the topical owner) and leave one-line pointers in other files retaining their unique specifics. Preserve all citations: superset-check by extracting every PR#/metric/file:line token before and after the merge.

45. **Codex farm-out pattern for research/doc-gen.** Write a tight brief to a temp file, run `codex exec --skip-git-repo-check --cd <dir> "$(cat promptfile)" < /dev/null` in the background; point it at a decisions single-source-of-truth so it doesn't re-derive settled decisions. Tell it NOT to `bd remember` -- the doc IS the artifact. Keep relationship-sensitive comment/Slack replies in the main session, never farmed out.

## Decision and proposal craft

46. **Separate CAPABILITY from MECHANISM, isolate the ONE concrete driver before scoping.** Adoption debates collapse when reframed from "use tool X" (mechanism) to "we need capability Y." Scope to the hard requirement before evaluating tools -- a whole-fleet takeover may be disproportionate to one service's need.

47. **Decision-doc tone: due-diligence-then-conclude, not advocacy.** "We explored it, it's overkill" reads better than "I don't want this." Run adversarial cross-model review (different model) to catch over-claims. Credit reviewer corrections and concede fast.

48. **Scale guardrail/security rigor to blast radius.** A greenfield dev-sandbox pilot needs "does the claim work, does retention work, does health reporting work" -- NOT permission-boundary design or threat models as go/no-go. Prod-grade hardening belongs on the path-to-prod, not in front of the pilot.

49. **For config-state claims, the LIVE cluster is authoritative; git/declared state is a hint.** A generic upstream claim was recorded as a fleet risk and took THREE passes to correct because only the live cluster `kubectl get` revealed a custom config making the risk a non-issue. Tag unverified claims `UNVERIFIED`.

50. **Don't let evidence for an EASY maturity layer launder as proof for a HARD layer.** "X+Y coexist" may be true at a shallow layer while saying nothing about your deeper combo (e.g. primary-CNI takeover + triple eBPF). Tag claims by maturity layer; absence of prior art for your exact combo is itself a finding.

51. **After heavy iterative pruning of a framework, run a consistency-grep pass.** Prune-heavy editing leaves scars: stale section names referencing demoted features, half-demoted rules restated in two places, and "thin wrapper" orchestrators that have re-accumulated methodology they were supposed to only point to.

## Self-tooling gotchas

52. **Unattended recurring jobs on macOS: launchd LaunchAgent, NOT CronCreate.** CronCreate jobs are session-bound (fire only while a REPL is open+idle) and auto-expire after ~7 days. launchd survives reboots. Threshold-guard the script and support a DRYRUN mode. GOTCHA: the safety classifier blocks the agent from installing a LaunchAgent that spawns an autonomous permission-bypass loop -- the user must install the plist.

## Shell and tooling portability

53. **BSD-vs-GNU coreutils divergence is the dominant portability hazard in shell scripts an agent writes, it only shows up when the script RUNS, and it fails silently in both directions.** macOS ships BSD coreutils but Homebrew commonly puts the GNU versions on `PATH`, so the same script sees a different tool depending on the machine and the shell. Two observed forms, both of which reported success: (a) **`sed -i '' 's|a|b|' file` is the BSD in-place form and GNU sed treats the empty string as the FILENAME**, so every "mutation" in a mutation suite was actually the clean baseline and the suite reported 10/10 caught; the same BSD-only form was then found in three more places in a migration script. (b) The inverse, inside an agent's Bash tool: the **empty-string argument is dropped before exec**, so BSD sed consumes the script as `-i`'s backup suffix and dies with `sed: can't read s|a|b|: No such file or directory` -- reproduced standalone on a one-line file, so it is not a large-output or wrapper artifact. **Portable replacement: `perl -i -pe` (use `\Q…\E` around any path with regex metacharacters), or an editor tool that verifies its own match, or `sed 's|a|b|' in > tmp && mv tmp in`.** Same family: **`df -g` is BSD-only** and a GNU `df` fails it with "invalid option" -- use POSIX `df -Pk` and divide. The general rule this cost us twice: **a green or red result from a mutation that never happened is worthless -- confirm the edit actually landed before trusting what the harness reports.**

54. **`yq` has two evaluation semantics that silently invert a check.** (a) **`//` returns its RHS when the LHS is `false`, not only when it is `null`**, so `forceDestroy: false` and an absent `forceDestroy` key are indistinguishable through `//` -- use `has("key")` for presence tests and never `//`. (b) **yq v4 binds `or` looser than `|`**, so `select(has(a) or has(b)) | "x"` parses as `select(has(a)) or (has(b) | "x")`: the select is escaped and the expression matches every document. Parenthesise the whole predicate. Both bugs make a filter match more than intended, which reads as a passing broad check rather than as an error.

55. **Portability bugs in an archive/restore script are found only by RUNNING it, and the expensive stateful step must come after all cheap validation.** From building a snapshot of a whole agent-harness environment (rsync to a tree first, then `tar -czf X -C $TREE .` from that tree, so the inspectable copy and the archive are the same bytes by construction): three defects surfaced, none by review. (1) A BSD-only `df` flag failed on a GNU `df` -- and that failure landed *before* the database-stop step purely because of ordering, which is the argument for putting every cheap check ahead of anything stateful. (2) `tar` refuses unix sockets (`pax format cannot archive sockets`) -- exclude `*.sock`. (3) **Exclude patterns are NOT portable between `tar` and `rsync`** (`tar` wants `*/name.pid`, `rsync` wants `name.pid`), and a silently non-matching exclude either bloats the archive or, if over-broad, eats real data -- **smoke-test excludes against fake data asserting BOTH that the junk is dropped AND that a sibling real file survives.** Operationally: stop any database daemon before archiving and restart it from an `EXIT` trap so every failure path leaves it up, and **warn on dirty git repos rather than refusing** -- uncommitted work is exactly what exists only on that disk.

## Verification method

56. **An empty result is evidence only after you have shown the query can match the thing you are looking for.** A failed query and an empty one are indistinguishable, and the failure always reads as the reassuring answer. Four observed shapes: (a) **zsh globs an unquoted `--include=*.tf`** and aborts `grep -r` with `no matches found` -- the search never runs and reports clean; quote the pattern. (b) **zsh globs an unquoted URL containing `?`**, so a `gh api` poll on `…/actions/runs?branch=X` dies the same way; combined with `|| true` the failed call left an empty status string, the "anything still queued?" grep matched nothing, and the monitor announced all runs terminal while six workflows were still running. **Never `|| true` into an empty variable in a poll loop -- use `|| echo APIFAIL` and branch on it.** (c) A CLI that returns a **summary view instead of a table** (`Passed: 12 / Failed: 0` with no per-check rows) makes a grep for a specific check name return empty, which reads exactly like "that required check never ran". (d) Searching for one phrasing of a stale premise returned clean while the premise survived in five other phrasings across nine entries -- **one phrasing is not a search.** The rule in all four: **pair every empty search with a positive control** -- a known-hit query run the same way, in the same scope, with the same quoting -- and report both numbers.

57. **A mutation suite that cannot mutate is indistinguishable from a perfect one.** Gate every mutation so a no-op hard-fails: apply the edit in a real language rather than a shell one-liner, `assert old in source` AND `assert mutated != original` before invoking the gate, print the mutation that was applied, and `cmp` the file against its pre-mutation copy. Then check the assertion itself is not accidentally satisfied: a needle that is a **substring of an unrelated message** passes while the thing it was meant to detect is gone -- searching for `"spec.aws.${k} is"` also matched `"is not a supported S3 managed resource"`, so deleting an entire security row still reported PASS. And ask the adversarial half, which is the one usually skipped: **not "does mutation X break the test" but "which mutations can this suite NOT see?"** A review of one chart test suite found 12 mutations that left every assertion green, including appending a wildcard-admin statement to an inline IAM policy -- because the assertions only read `.Statement[0]`. **For any security surface, assert the full statement or rule SET, never an index.**

## Numbered-corpus hygiene

58. **Silent mis-resolution is more dangerous than a dangling reference, and only a DIFFERENTIAL detector finds it.** `core/protocols/knowledge-tiers.md` ("Tombstoning") covers why you never renumber; this is the detection half, and the case it does not cover: **copying entries between two corpora that number independently.** A bare `#N` pasted across that boundary does not 404 -- if `N` happens to be within the destination's range it resolves to a real but unrelated entry, reads as authoritative, and is invisible to any dangling-reference scan. **Strip or re-resolve every cross-reference at the boundary; a range check is not a resolution check -- open the target and confirm it is the same idea.** The method that makes these findable at scale: **diff the detector's output against a pre-change snapshot.** Absolute counts are meaningless -- a first run can report hundreds of suspect references, nearly all of which predate your change -- and only the delta between the two runs is actionable. A detector with no baseline produces a number nobody can act on, and the honest report separates "references my change created" (should be zero) from "pre-existing, found in passing."

59. **Duplicate entry numbers accumulate silently in any long-lived numbered corpus, and they make every citation to that number ambiguous.** They arrive through concurrent appends, through merges, and through entries inserted mid-file rather than at the end. Audit for them mechanically -- `grep -oE '^[0-9]+\. ' file | sort -n | uniq -d` -- as a standing check, not once. The fix is never renumbering (see the tombstoning rule above): flag the collision, assign the next free number to the newer entry, and leave the rest alone.

60. **A correction pasted beside the wrong text leaves both standing.** Appending "NOTE: the above is wrong, actually X" produces a document that asserts two contradictory things, and a reader (or an agent) arriving by grep will find whichever one their pattern hit. **Amendments must edit in place**: change the claim, then note what changed and why, so the corpus never contains both versions as live text. Marking a superseded entry is fine -- carrying it as an unmarked equal alternative is not.

61. **"Already covered" requires a citation, not a feeling.** When deciding whether an insight is already recorded, the reviewer must name the exact entry and quote the line being relied on; if they cannot quote it, it is not covered. Two measured passes make the size of the effect clear: a pass that judged coverage by impression graded far more items as already-generalized than two later passes that demanded a quotable reference, which found only 12 of 130 and 9 of 143 genuinely covered. A keyword sweep for the specific terms in the "covered" bucket returned zero hits across the entire destination corpus. **The same rule applies to the destination check itself: write the entry, then grep the destination file to confirm it landed, and only then delete the source.** Never delete on the strength of intending to write.

## Persistence layers and maintenance commands

62. **A tool's auto-export can exclude an entire record class, and a cold start rebuilds from that export.** A knowledge store exported issues and memories to one canonical file, but the default `export` wrote issues only -- memories were dropped as "possibly sensitive" unless `--all` was passed. Nothing was lost, because the live store remained authoritative, but **anything rebuilding from that file would have restored an empty memory store.** Observed twice, days apart, the second time *after* an export had been verified correct: a later plain export in the same session silently rewrote the file back to issues-only. **Generalise: verify after the FINAL export, not the first.** A one-line assertion is enough -- count the records of the class you care about in the exported artifact and fail if it is zero -- and it belongs at the end of the run, after every writer has finished. For backups, take both the tool's supported backup path and an explicit full export into the archive; a raw copy of the store directory is not a restore path.

63. **A maintenance command can return rc=0 and do nothing, because it was run one directory above the thing it maintains.** A storage-reclaim command run at the server root of a database exited clean, printed no warning, and reclaimed 0 of 140 MB -- the actual database lives one level down, and at the server root there was a same-shaped directory with nothing in it, so the command "succeeded" on an empty working set. Run from the database directory the same command took the store from 140 MB to 31 MB and restored a per-operation cost that had degraded roughly fourfold. **A zero exit that does nothing is the worst kind of maintenance command: it is indistinguishable from "already clean".** Always pair a reclaim with a before/after size measurement, and assert the reclaim actually moved the number rather than trusting the exit code.

64. **A health check that counts by grepping a tool's human-readable output becomes a silent no-op the moment that tool changes format, and it fails in the reassuring direction.** A drift check counted records with `<tool> list | grep -c '^### '`; the tool stopped emitting that prefix, the count was zero from then on, the threshold was therefore never exceeded, and the check reported all-clear against a live store well over its limit. Three rules: (1) **count from a machine-readable surface** (`--json`, `--porcelain`) and never from formatted text; (2) **distinguish "zero" from "could not measure"** -- return a sentinel on parse failure and WARN, because a check that cannot run must never render as a pass; (3) **test every threshold with two controls** -- one that forces it to fire, and one that breaks the measurement itself. A gate whose failure mode is silence is indistinguishable from a healthy system.
