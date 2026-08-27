# Parallel Dispatch Protocol

When the same operation needs to run across N independent targets — clusters, services, components, regions, dashboards, charts — dispatch N specialist or worker sub-agents in parallel rather than serially.

## When to parallelize

Parallelize when **all** of these are true:

- The targets are independent: no shared state, no ordering requirement.
- Each target uses the same playbook with target-specific parameters.
- Results can be aggregated afterwards by the orchestrator.

Examples that fit:

- Validating a configuration across N clusters.
- Auditing N services for the same readiness criteria.
- Generating N dashboards from the same template.
- Building N Helm charts that share a wrapper pattern.
- Reviewing N PRs against the same checklist.

Examples that do **not** fit:

- A → B → C dependency chains.
- Operations against shared global state (a single chart, a single PR).
- Anything that mutates the same file path concurrently.

## Dispatch shape

In the orchestrator (often `task-planner` or the main session):

1. Pick a single, sanitized playbook (numbered checks, exact commands, pass/fail criteria, evidence).
2. Build per-target parameter sets — keep them small.
3. Launch all worker dispatches **in one message** so the runtime can fan them out.
4. Wait for every worker to return before aggregating.
5. Produce a single consolidated handoff report keyed by target.

## Worker prompt template

```markdown
Goal: <one sentence>
Target: <cluster | service | dashboard | chart>
Parameters: <target-specific values>
Playbook: <link to a numbered checklist with commands and expected evidence>
Constraints:
- Read-only unless explicitly told otherwise.
- No mutating Kubernetes / Helm / git operations.
- Sanitize before returning (no real identifiers, tokens, URLs).
Verify by:
- <check 1>: <pass/fail criterion>
- <check 2>: <pass/fail criterion>
Return: structured handoff (see core/protocols/safety-and-handoff.md).
Before finishing, persist any non-obvious finding:
bd remember "<insight>" --key <repo>/<prefix>/<topic>
```

## Aggregation in the orchestrator

After all workers return:

1. Diff per-target results against the playbook's pass/fail criteria.
2. Surface only what differs — a green matrix is enough for the rest.
3. Flag any worker that timed out or returned a `Blockers` section instead of `Changes`.
4. File follow-up `bd` tasks for each failed target before closing the parent task.

## Two-phase fan-out: parallel classifiers, one serial applier

The "no shared state" precondition above is stricter than it looks. Many backends that *appear*
per-record are globally stateful — a store whose every invocation re-imports a shared export file
with upsert semantics will let one worker's read silently resurrect a record another worker just
deleted. The write reports success; the deletion is simply gone on the next read.

When the targets are independent but the *destination* is not, split the work in two:

1. **Phase 1 — parallel, read-only.** Each worker classifies its own slice and writes a
   **proposal file** to disk. Zero mutations of the shared store, zero writes into the
   destination tree. Workers may read anything; they may write only their own proposal file.
2. **Phase 2 — serial, single writer.** The orchestrator reads every proposal and applies them
   itself, one at a time, in one process.

This is also the answer whenever workers would otherwise edit the same branch, the same PR, or the
same file. Two writers on one branch produce interleaved commits, lost edits, and a diff nobody
can review. **Fan out the reading; keep every write in one place.** Work that genuinely needs
parallel writes needs separate branches and separate PRs — that is a decision for the human, not
something to solve with more workers.

### Shard by destination, not by source

When phase 1 workers produce content that lands in files, partition the work by **which file the
output goes into**, not by which file the input came from. One owner per destination file is what
makes the applier race-free and makes an incomplete result diagnosable: a destination with no
proposals is visibly missing an owner, whereas a source split across three workers leaves nobody
accountable for any particular output.

### The per-item manifest is the gate

Require every phase-1 worker to return **one manifest row per work item** — item id, disposition,
destination, and the evidence for the disposition. Not a summary; a row per item.

This is the check that catches the orchestrator's own mistakes, not just the workers'. In one pass
the manifest surfaced seven items with **no owner at all** — the dispatch prompts had omitted a
source file, so no worker had ever seen them. Without the manifest they would have been deleted
along with everything else in the batch, their content never written anywhere. A worker cannot
report a gap in a partition it was never told about; only reconciling every item against the
manifest finds it.

Two rules that make the manifest trustworthy:

- **Assert the partition in code before writing anything.** Build the classification map
  programmatically and assert that the union of every bucket equals the input list exactly — no
  duplicates, no gaps. Every worker that did this caught a real error, including a hand count that
  was off by one across 145 items.
- **A manifest row is a claim, not a fact.** Re-derive it: confirm the proposed ids match the
  claimed ids, and resolve every asserted reference against the live destination rather than
  trusting the string. See `agent-knowledge/references/learnings-agent-workflow.md` on
  silent mis-resolution — a reference that is merely *in range* resolves to the wrong thing
  without erroring.

### Let workers refute the prior

State your working hypothesis in the dispatch prompt — workers orient much faster with one — but
**write the prompt so that refuting it is an acceptable, expected outcome**, and say so explicitly.
An independent verifier that can only confirm what the dispatcher implied is worth nothing.

This pays off in practice. Given a stated prior about how a body of material was structured, two
workers came back with evidence that the prior was wrong, and they were right. In a separate
fan-out, two workers corrected the *dispatch prompt itself* rather than the claim under test —
the orchestrator had asserted the existence of something that did not exist at the version in
scope. Related: a worker that reports its check as BLOCKED and says plainly which part of its
answer came from documentation rather than an empirical result is giving you a weighable verdict.
Reward that; a confident worker with an unmarked gap is the more expensive outcome.

## Why this matters

A well-structured playbook plus parallel workers turns hours of sequential investigation into minutes of fan-out and a clean diff. Empirical observation: a 12-check mTLS readiness playbook run across 3 clusters in parallel completes in ~5 minutes vs ~45 minutes sequential — **3x+ wall-clock speedup**. Creation cost (~1 hour) was amortized across every subsequent run.

Two heuristics:

- If you find yourself doing the same investigation more than twice, write the playbook.
- If a playbook needs to run across more than two independent targets, fan it out.

## Validation playbooks are the highest-ROI artifact

A well-structured playbook (numbered checks, pass/fail criteria, specific commands/queries per check) can be executed by any agent instance with no additional context. The playbook is the unit of leverage; parallel dispatch is how you apply it at scale.
