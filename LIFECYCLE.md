# Context Lifecycle — How Memory Survives Compaction

The whole point of `bd` + the harness hooks is that **nothing important is lost when the context window compacts.** This page is the canonical narrative.

## TL;DR

```
during work        ─► bd remember "<insight>" --key <repo>/<prefix>/<topic>
threshold crossed  ─► ctx-threshold-warn.py nudges /compact
compaction         ─► pre-compact-bd-sync.py snapshots PRs/tasks/tickets into bd memory
                                                + adds comment to every in-progress bd task
next session       ─► post-compact-prime-reminder.sh runs bd prime; agent reloads memories + ready queue
```

The result: the agent forgets the chat, but remembers **what it learned, what tasks were in flight, and what blockers remain**.

## Full flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   1. SESSION START                                                           │
│   ───────────────                                                            │
│                                                                              │
│   ┌─────────────────────────┐                                                │
│   │ post-compact-prime-     │   reloads workflow context, durable memories,  │
│   │ reminder.sh             │──►  ready tasks, in-progress task comments     │
│   │ (or manual bd prime)    │                                                │
│   └─────────────────────────┘                                                │
│            │                                                                 │
│            ▼                                                                 │
│   Agent now sees the full operating context without scrolling chat history.  │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   2. DURING WORK                                                             │
│   ──────────────                                                             │
│                                                                              │
│   Agent does the task. Whenever a non-obvious learning emerges, it writes:   │
│                                                                              │
│       bd remember "<self-contained insight>" --key <repo>/<prefix>/<topic>   │
│                                                                              │
│   Key prefixes (see core/protocols/bd-and-memory.md):                        │
│                                                                              │
│       decision/  trouble/  tool/  lesson/  pref/  security/  perf/           │
│                                                                              │
│   Tasks get progress comments:                                               │
│                                                                              │
│       bd comments add <task-id> "<what changed, what was verified, next>"    │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   3. CONTEXT FILLS UP                                                        │
│   ───────────────────                                                        │
│                                                                              │
│   ┌─────────────────────────┐                                                │
│   │ ctx-threshold-warn.py   │   reads transcript via statusline-context.py,  │
│   │ (UserPromptSubmit hook) │──►  computes utilization, nudges /compact when │
│   │                         │     past CTX_COMPACT_THRESHOLD (default 85%)   │
│   └─────────────────────────┘                                                │
│            │                                                                 │
│            ▼                                                                 │
│   Agent decides to compact at a quiet moment — not mid-tool-chain.           │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   4. COMPACTION                                                              │
│   ─────────────                                                              │
│                                                                              │
│   ┌─────────────────────────┐                                                │
│   │ pre-compact-bd-sync.py  │   parses the JSONL transcript:                 │
│   │ (PreCompact hook)       │                                                │
│   │                         │   • extracts PR numbers, bd task IDs, tickets  │
│   │                         │   • detects clusters/actions touched           │
│   │                         │   • writes a session/pre-compact memory        │
│   │                         │   • appends a snapshot comment to every        │
│   │                         │     in-progress bd task                        │
│   │                         │   • runs bd sync                               │
│   └─────────────────────────┘                                                │
│            │                                                                 │
│            ▼                                                                 │
│   Memory store now contains a structured snapshot of THIS session, keyed     │
│   so the next session can pick it up.                                        │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│   5. NEXT SESSION                                                            │
│   ───────────────                                                            │
│                                                                              │
│   Loop back to step 1. bd prime surfaces the snapshot. No context loss.      │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Deliberate checkpointing (don't rely on the hook alone)

The hooks are the safety net, not the whole story. When context is high, a long turn is ending, or a task has meaningful in-flight state, the agent should **checkpoint deliberately** — `bd remember "<state, decisions, blockers, next action>" --key <repo>/pre-compact` plus a checkpoint comment on the in-flight task — before compaction fires. The hook can snapshot PRs and task IDs from the transcript, but only a deliberate checkpoint captures the *reasoning*. Full steps are in the "Pre-compaction / context-loss checkpoint" section of [`core/protocols/bd-and-memory.md`](core/protocols/bd-and-memory.md).

## Why this matters

A 30-minute infra session can pump 100k+ tokens of `kubectl describe`, `helm template`, and `git diff` into context. Without durable memory:

- Compaction loses subtle decisions ("we chose CRD X over Y because Z").
- Hand-offs across agents lose context.
- The next session re-discovers the same problem.

With this loop:

- Every non-obvious finding lands in `bd remember`.
- Every in-progress task carries its own snapshot.
- The next session begins with full operating context in a fraction of the tokens.

## Two cadences: bd memory + curated knowledge base

`bd remember` is the **firehose** — fast, per-session, captured without overthinking format. The [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)-style local knowledge base in [`agent-knowledge/references/`](agent-knowledge/references/) is the **curated stream** — numbered, append-only `learnings-*.md` files that future agents read first. The promotion path (recurring `bd` memory → numbered learning) is documented in [`agent-knowledge/references/README.md`](agent-knowledge/references/README.md). Together they cover both "what I just learned" and "what we have always known."

### Explicit post-task step (every sub-agent)

The end of every non-trivial task runs the four-step **Task Completion Checklist** (canonical in [`core/protocols/bd-and-memory.md`](core/protocols/bd-and-memory.md)):

```
1. bd remember "<self-contained insight>" --key <repo>/<prefix>/<topic>
2. Append one line to agent-knowledge/references/log.md
3. Update or CONFLICT-flag the relevant agent-knowledge/references/learnings-*.md item
4. Update agent-knowledge/references/index.md only if a doc was added or removed
```

The handoff report has a mandatory `## Knowledge updates` section ([`templates/handoff-report.template.md`](templates/handoff-report.template.md)). Agents must list what they changed, or write `None.` next to each row — never omit the section. This is the gate that keeps the curated stream alive instead of letting it ossify.

## The pieces

| Piece | Path | Role |
| --- | --- | --- |
| `bd prime` workflow | [`core/protocols/bd-and-memory.md`](core/protocols/bd-and-memory.md) | Canonical rules for tasks, comments, memories, key taxonomy |
| Pre-compact hook | [`core/hooks/factory-droid/pre-compact-bd-sync.py`](core/hooks/factory-droid/pre-compact-bd-sync.py) | Parses transcript, writes memory + task snapshots at compaction time |
| Threshold warn hook | [`core/hooks/factory-droid/ctx-threshold-warn.py`](core/hooks/factory-droid/ctx-threshold-warn.py) | Nudges `/compact` at `CTX_COMPACT_THRESHOLD` |
| Session-start hook | [`core/hooks/factory-droid/post-compact-prime-reminder.sh`](core/hooks/factory-droid/post-compact-prime-reminder.sh) | Reloads bd context after compaction |
| Transcript parser | [`core/statusline/statusline-context.py`](core/statusline/statusline-context.py) | Shared utilization computation for statusline and threshold hook |
| Generic helper | [`core/hooks/generic/post-task-memory.sh`](core/hooks/generic/post-task-memory.sh) | Runtime-agnostic `bd remember` wrapper |
| Tool reference | [`tools/bd/README.md`](tools/bd/README.md) | Upstream install + memory conventions |

## Adopting the lifecycle

The hooks above are Factory Droid examples. For your runtime:

- Wire **session start** to run `bd prime` (every adapter README shows the location).
- Wire **pre-compaction** to the equivalent of `pre-compact-bd-sync.py`. If the runtime has no PreCompact hook, run `bd sync` on a timer.
- Wire **user-prompt-submit** or whatever inspects context size to the threshold-warn pattern.

If your runtime supports none of the above, the manual flow still works — just run `bd remember` deliberately and `bd prime` at session start. The hooks just make it harder to forget.

## Sample memory

```
$ bd remember --search "graphify"
[1] <repo>/lesson/graphify-first
    For architecture and dependency questions, query graphify-out/graph.json first.
    File-by-file reads cost ~70x more tokens for the same answer.

[2] <repo>/decision/graphify-not-truth
    Graphify guides exploration; source files remain the final authority.
    Verify against source before editing.
```

Two lines in memory replace re-discovering a pattern across multiple sessions.
