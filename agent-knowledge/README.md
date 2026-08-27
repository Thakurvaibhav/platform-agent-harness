# `agent-knowledge/` — shared agent knowledge home

The harness-neutral **source of truth** for everything agents read before they
grep a repo: protocols, topic learnings, tool guides, the knowledge-home
scripts, and usage telemetry. It is shared by **all** runtimes (Factory
Droid, Claude Code, and any CLI agent that can read files and run shell).

**Edit canonical files here — never duplicate them into a runtime-specific dir.**
A runtime points *at* this home; it does not own a private copy.

## Layout

| Dir | Contents |
| --- | --- |
| [`references/`](references/) | **Portable tier.** Always-load protocols (the `index.md` catalog, `log.md` chronology) + topic learnings (`learnings-*.md`) + tool guides — method and vendor behavior that travels across employers. The hand-curated [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)-style knowledge base (see [`references/README.md`](references/README.md)). |
| [`orgs/`](orgs/) | **Instance tier.** One directory per employer/client/estate: cluster registries, account IDs, fleet inventories, metric allowlists — facts true of one environment and nowhere else. See [`orgs/README.md`](orgs/README.md); the rule that decides which tier a fact belongs to is [`core/protocols/knowledge-tiers.md`](../core/protocols/knowledge-tiers.md). |
| [`env.sh`](env.sh) | The one place that knows this machine's paths: `WORK_ROOT`, `BEADS_DB`, `HARNESS_HOME`, `HARNESS_DOCS`, `JIRA_BASE_URL`, `ACTIVE_ORG`. Sourced by the login shell and by the scripts directly. **Changing machine or employer should be an edit here, not a grep across the harness.** |
| [`scripts/`](scripts/) | `knowledge-search.sh` (search bd memories + both knowledge tiers + reading notes + domain docs), `drift-check.sh` (staleness warnings), `learn.sh` (one-liner learning capture), `codex-dispatch.sh` (cross-runtime sub-agent parity), `codex-session-prime.sh` (Codex SessionStart bd-prime hook), `auto-consolidate.sh` (scheduled consolidation runner). The knowledge scripts honor the `HARNESS_REFS` env var and default to this home's `references/`. |
| [`metrics/`](metrics/) | Usage telemetry written by the learning-gate hook: per-file read counts (`learning-reads.json`/`.jsonl`, primary) + per-entry citation counts (`learning-usage.json`/`learning-citations.jsonl`). Drives consolidation ranking + gap-detection (never pruning). See [`metrics/README.md`](metrics/README.md). |
| [`reading/`](reading/) | External-source reading notes (distilled, vetted articles/papers/talks) — a **separate trust tier** from `references/` (external, curated, not yet proven in your stack). Written by the `ingest-reading` skill; cataloged in [`reading/index.md`](reading/index.md). |

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
install time you create a real home — e.g. `~/.agent-knowledge/{references,orgs,scripts,metrics,reading}`
(any path works) — copy or seed these contents into it, and point every runtime
at that path (Factory via symlinks, Claude via direct paths, generic via
`HARNESS_REFS`). Set the machine's paths once in [`env.sh`](env.sh);
`knowledge-search.sh` resolves its home relative to itself, so it is not pinned
to `~/.agent-knowledge` (the other scripts still default to that path — override
with `HARNESS_REFS`). Runtime wiring lives in [`adapters/`](../adapters/) and
[`installation/`](../installation/).

Real `orgs/<org>/` content is instance knowledge and stays in the deployed home —
this repo ships only [`orgs/README.md`](orgs/README.md). Re-pointing a deployed
home at a new employer is [`installation/new-org-setup.md`](../installation/new-org-setup.md).
