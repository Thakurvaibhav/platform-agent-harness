# Agent Operating Contract (TEMPLATE)

> **This is a template.** Copy this file into the root of your infra repo as `AGENTS.md` and customize the placeholders for your environment. The cross-tool `AGENTS.md` standard is supported by Codex CLI, OpenCode, Goose, Claude Code (alongside `CLAUDE.md`), and newer Aider releases. See `adapters/` in the harness for runtime-specific wiring.
>
> When you copy this file, also copy or symlink the referenced directories (`core/agents/`, `core/protocols/`, `skills/`, `domain-packs/`, `agent-knowledge/references/`) into your repo, or adjust the paths to match where you place them.

Use this file as the root instruction contract for CLI agents working in platform / infrastructure repositories.

## Startup

At session start or resume, every agent — main session and sub-agent — does the following before any task work:

1. Read [`core/protocols/bd-and-memory.md`](../core/protocols/bd-and-memory.md) for the shared protocols: code quality (Assumptions, Simplicity, Reuse-First, Surgical Changes), constraints, bd workflow, memory taxonomy, verification (goal-driven execution), and the completion checklist.
2. Read [`agent-knowledge/references/index.md`](../agent-knowledge/references/index.md) to discover available reference docs — agents check the index **before** broad searches so existing knowledge is reused, not re-derived.
3. **Knowledge search** — run [`agent-knowledge/scripts/knowledge-search.sh`](../agent-knowledge/scripts/knowledge-search.sh) `<task keywords>` to find prior art across bd memories, learnings files, and domain docs.
4. Read [`agent-knowledge/references/clusters.md`](../agent-knowledge/references/clusters.md) (or your repo's equivalent) before any cluster-scoped decision.
5. If `graphify-out/graph.json` exists in the repo, load it for architecture and dependency questions.
6. **Drift check** (orchestrator only, at session start/resume) — run [`agent-knowledge/scripts/drift-check.sh`](../agent-knowledge/scripts/drift-check.sh). Surface warnings to the user before starting work. Do not auto-fix without approval.

For the wider operating model (the seven pillars), see [`core/protocols/harness-pillars.md`](../core/protocols/harness-pillars.md). For the compaction lifecycle, see [`LIFECYCLE.md`](../LIFECYCLE.md).


## Operating principles

- Treat the harness as a behavioral specification and coordination protocol around the agent: agents, skills, task state, memory, knowledge index, graph context, validation, and safety all work together.
- Prefer specialist sub-agents for specialist work.
- Query `graphify-out/graph.json` before broad repo exploration when it exists.
- Use `bd` for task state, comments, dependencies, and durable memory.
- Check `agent-knowledge/references/index.md` before broad searches so existing knowledge is reused.
- Use `rtk` for simple read-only verbose commands; do not wrap mutating, piped, chained, interactive, or exact-output-sensitive commands.
- Keep changes surgical and verifiable.
- Never expose secrets, internal identifiers, cluster names, account IDs, customer names, or private URLs.

## Harness pillars

The canonical operating model is in [`core/protocols/harness-pillars.md`](../core/protocols/harness-pillars.md): specialist agents, bd task/memory state, indexed knowledge, Graphify-first exploration, skills, safety/validation gates, and token economics. The compaction lifecycle is in [`LIFECYCLE.md`](../LIFECYCLE.md).

## Delegation policy

| Work type | Sub-agent |
| --- | --- |
| Project planning and task breakdown | `task-planner` |
| Tool research and production readiness | `tool-researcher` |
| Helm chart authoring and upgrades | `helm-engineer` |
| ArgoCD applications and GitOps enablement | `argocd-engineer` |
| CI, alerting, dashboards, observability | `platform-engineer` |
| PR review and CI feedback | `pr-reviewer` |
| General-purpose engineering, research, validation | `general-engineer` |

Contract or milestone validation runs via the `contract-validation` skill — no dedicated validator agent required.

## Safety rules

- Do not run mutating Kubernetes commands unless the human explicitly asks and the repo policy allows it.
- Do not run `helm install`, `helm upgrade`, `helm uninstall`, or rollback commands by default.
- Do not push to `main` or `master`.
- Do not force-push protected branches.
- Treat untracked files as user-owned.
- Review diffs for secrets before committing or publishing.

## Task state

Use `bd` for all non-trivial work:

```bash
bd prime
bd ready
bd update <id> --claim
bd comments <id>
bd comments add <id> "<status>"
bd remember "<self-contained learning>" --key <repo>/<category>/<topic>
bd close <id> --reason "<reason>"
```

Avoid commands that open an editor (e.g. `bd edit`).

## Learning capture (enforced)

Persist the moment you hit something non-obvious — a gotcha, a non-obvious fix, or a decision and its rationale. Batching to task end loses them.

- **Fastest path:** `agent-knowledge/scripts/learn.sh "<insight>" <domain>/<category>/<topic>` (a low-friction `bd remember` wrapper). `bd remember` directly also works.
- **Reusable engineering knowledge** belongs in `agent-knowledge/references/learnings-*.md`; **operational/uncertain** state in `bd`; **runtime-only config trivia** in runtime-native memory. See "Memory routing" in [`core/protocols/bd-and-memory.md`](../core/protocols/bd-and-memory.md). Never write the same fact to two stores.
- **Machine-enforced** via [`core/hooks/generic/learning-gate.py`](../core/hooks/generic/learning-gate.py): a hard gate for sub-agents (blocks stop once if substantive work persisted nothing) and a soft nudge for the main session.
- **Cite, don't re-explain.** Reference existing entries as `[learnings-<file>.md#<N>]`; citations logged to `agent-knowledge/metrics/learning-usage.json` drive consolidation pruning, so citing beats restating.
- **Kill switch:** `LEARN_GATE_DISABLE=1` disables gating and nudging.

## Graphify-first workflow

When `graphify-out/graph.json` exists:

```bash
graphify query "<architecture question>"
graphify path "<node-a>" "<node-b>"
graphify explain "<node>"
```

Use the graph to choose files to inspect instead of reading entire repositories file by file.

## Command policy

Classify every shell command before running it:

- `native-tool`: use the agent's `Read` / `Grep` / `Glob` / `LS` tools instead of shell.
- `rtk-safe`: simple read-only verbose command — prefix with `rtk`.
- `raw-required`: mutating, piped, chained, exact-output-sensitive, or interactive command — run raw.

## Handoff contract

Every non-trivial sub-agent run ends with:

```markdown
## Summary
<what was done>

## Changes
- <file/resource>: <why>

## Verification
- <command/check>: <pass/fail/skipped> — <evidence>

## Artifacts
- bd task: <id/status>
- PR: <url if any>

## Open questions / follow-ups
- <items or "None.">
```

## Sanitization rule

Before sharing any harness content publicly, run [`sanitization/prepublish-checklist.md`](../sanitization/prepublish-checklist.md): `trufflehog`, `gitleaks`, and the local denylist.
