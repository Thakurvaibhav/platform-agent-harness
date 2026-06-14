# `agent-knowledge/` — shared agent knowledge home

The harness-neutral **source of truth** for everything agents read before they
grep a repo: protocols, topic learnings, tool guides, the knowledge-home
scripts, and the citation heatmap. It is shared by **all** runtimes (Factory
Droid, Claude Code, and any CLI agent that can read files and run shell).

**Edit canonical files here — never duplicate them into a runtime-specific dir.**
A runtime points *at* this home; it does not own a private copy.

## Layout

| Dir | Contents |
| --- | --- |
| [`references/`](references/) | Always-load protocols (the `index.md` catalog, `log.md` chronology) + topic learnings (`learnings-*.md`) + tool guides. The hand-curated [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)-style knowledge base (see [`references/README.md`](references/README.md)). |
| [`scripts/`](scripts/) | `knowledge-search.sh` (search bd memories + learnings + domain docs), `drift-check.sh` (staleness warnings), `learn.sh` (one-liner learning capture). All honor the `HARNESS_REFS` env var and default to this home's `references/`. |
| [`metrics/`](metrics/) | Citation heatmap written by the learning-gate hook (`learning-usage.json` + `learning-citations.jsonl`). Drives usage-based consolidation pruning. See [`metrics/README.md`](metrics/README.md). |

## How each runtime reaches it

- **Factory Droid** — its historical paths (the runtime's `references/` and
  `scripts/` dirs) are **symlinks** into this home, so Factory keeps working
  unchanged.
- **Claude Code** — its `CLAUDE.md`/`AGENTS.md`, agents, skills, and hooks
  reference these paths **directly**.
- **Generic runtimes** — point at the home with the `HARNESS_REFS` env var (the
  scripts honor it) or a symlink from wherever the runtime expects its
  references.

## Not stored here

- **bd / beads operational memory** — task state, comments, and per-session
  `bd remember` notes. That store is tool-agnostic and lives in the repo's
  `.beads` database (git-synced, so it is shared across runtimes via the repo,
  not via this home).
- **Runtime-specific config trivia** — settings, hook wiring, and
  machine-local facts belong in that runtime's own dir / native memory, not
  here.

See [`references/learnings-*.md`](references/) for durable engineering patterns
and `core/protocols/bd-and-memory.md` → "Memory routing" for which store to use
for what.

## Deployment note

This `agent-knowledge/` directory is the **template** for the deployed home. At
install time you create a real home — e.g. `~/.agent-knowledge/{references,scripts,metrics}`
(any path works) — copy or seed these contents into it, and point every runtime
at that path (Factory via symlinks, Claude via direct paths, generic via
`HARNESS_REFS`). Runtime wiring lives in [`adapters/`](../adapters/) and
[`installation/`](../installation/).
