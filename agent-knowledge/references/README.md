# Local Knowledge Base for Agents

A small, markdown-only knowledge base that the agents read **before** searching the repo. Three pieces, all hand-curated:

| File | Role |
| --- | --- |
| [`index.md`](index.md) | Master catalog of every reference doc, with one-line descriptions. Agents grep this first. |
| [`log.md`](log.md) | Append-only chronology of non-trivial work (one line per task). Audit trail. |
| `learnings-*.md` | Numbered, append-only learnings per domain. Each item is a self-contained insight. |

## Inspiration

This is a direct adaptation of [**Andrej Karpathy's LLM Wiki**](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern: keep knowledge in plain markdown, hand-curated, and let the LLM query it instead of building a RAG pipeline over it. The harness applies that idea to multi-agent platform engineering:

- The `index.md` is the wiki's table of contents.
- The `learnings-*.md` files are the wiki entries, organized by domain.
- The `log.md` is the changelog so future agents see what shipped recently.

Karpathy's argument is that for a small, hand-curated corpus (hundreds of files, not millions), a structured markdown set the LLM reads on demand beats a vector-DB RAG pipeline on both precision and maintainability. The harness shares that bet — and pairs it with `bd remember` for memories generated *during* sessions.

## How it composes with `bd`

Two layers, two cadences:

- **`bd remember`** — fast, per-session capture. Agents write memories during a task without thinking about formatting. Survives compaction via the [PreCompact hook](../../core/hooks/factory-droid/pre-compact-bd-sync.py).
- **`agent-knowledge/references/learnings-*.md`** — slow, deliberate, append-only. A human (or a high-trust agent) promotes a recurring `bd` memory into a numbered learning when it becomes a durable pattern.

So `bd` memories are the firehose; `learnings-*.md` is the curated stream that future sessions actually read first.

## Operating rules

### `index.md`

- Every doc in the harness has a row.
- Add a row when you create a doc. Remove the row when you delete one. Never reorganize style.
- Format: `| <path> | <one-line purpose> |`.
- Grouped by section (root, protocols, agents, skills, domain packs, tools, hooks, installation, adapters, templates, examples, sanitization). Keep groupings stable.

### `log.md`

- One line per non-trivial task. Trivial / read-only / mission-scoped tasks: skip.
- Format:
  ```
  ## [YYYY-MM-DD] <type> | <repo> | <one-line summary> [bd:<id>] [pr:<#>]
  ```
- Types: `rollout` | `research` | `bugfix` | `docs` | `refactor` | `upgrade` | `enablement` | `audit` | `harness`.
- Append-only. Do not rewrite history.

### `learnings-*.md`

- Numbered, append-only.
- **Update the existing entry — never duplicate.** If a new finding refines an existing item, edit that item.
- Each item is self-contained: a future session must understand it without context.
- If a new finding conflicts with an existing entry, flag the conflict in the handoff (`CONFLICT: ... vs learnings-<file>.md#<n>`). The human decides; do not silently rewrite.

### Promotion path (`bd remember` → `learnings-*.md`)

**Immediate ingest (primary path):** Promote during the same session when ingest trigger conditions are met (see "Knowledge Ingest" in [`core/protocols/bd-and-memory.md`](../../core/protocols/bd-and-memory.md)). Don't defer when the insight is clear and actionable.

**Consolidation (catch-all):** Periodic consolidation catches memories that weren't promoted immediately — uncertain findings that settled, patterns that only became clear across multiple sessions, or sessions where ingest was skipped.

A memory earns a numbered entry when:

1. It would have saved >10 minutes if known earlier, or
2. A tool or API behaved differently than documented, or
3. An architectural decision was made with tradeoffs worth recording, or
4. A non-obvious root cause was uncovered during debugging.

**Provenance:** Append `(ref: #NNN)` or `(ref: <url>)` when the entry derives from a specific PR, issue, or external doc. Skip for general experience-derived lessons.

**Convention:** `See also:` cross-reference pointers go in the file header, immediately after the opening description paragraph. Single line format: `See also: \`learnings-foo.md\`, \`learnings-bar.md\``.

## How agents actually use this

A typical sub-agent startup, per [`core/protocols/bd-and-memory.md`](../../core/protocols/bd-and-memory.md):

1. Read this `index.md` to discover what reference docs exist.
2. Read the domain `learnings-*.md` files named in your agent prompt.
3. Run `bd prime` to load fresh memories from prior sessions.
4. Start the task.

The two slow files (`index.md`, `learnings-*.md`) cover the durable institutional knowledge. The fast files (`bd` memories + this session's transcript) cover the per-task context. Together they give the agent the equivalent of a teammate's "I've been doing this for years" without burning that context every session.

## Why this beats the alternatives

| Alternative | Why we don't use it |
| --- | --- |
| Vector DB + RAG | Overkill for a hand-curated corpus this size; harder to audit; ranks irrelevant chunks above the right one when the corpus is small. |
| One giant `AGENTS.md` | Doesn't scale past ~10 KB; agents lose the latter half. The index + learnings split keeps each file small and on-topic. |
| Per-repo runbooks alone | Project-local, not portable. Learnings here are reusable across every repo using the harness. |

## Public sharing rule

The harness ships sanitized learnings (no real cluster names, ticket prefixes, customer names, internal URLs). Before publishing any derivative learnings file, run [`sanitization/prepublish-checklist.md`](../../sanitization/prepublish-checklist.md).
