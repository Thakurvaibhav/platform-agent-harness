# Agent Operating Contract (TEMPLATE)

> **This is a template.** Copy this file into the root of your infra repo as `AGENTS.md` and customize the placeholders for your environment. The cross-tool `AGENTS.md` standard is supported by Codex CLI, OpenCode, Goose, Claude Code (alongside `CLAUDE.md`), and newer Aider releases. See `adapters/` in the harness for runtime-specific wiring.
>
> When you copy this file, also copy or symlink the referenced directories (`core/agents/`, `core/protocols/`, `skills/`, `domain-packs/`, `references/`) into your repo, or adjust the paths to match where you place them.

Use this file as the root instruction contract for CLI agents working in platform / infrastructure repositories.

## Operating principles

- Treat the harness as an operating system around the agent: agents, skills, task state, memory, knowledge index, graph context, validation, and safety all work together.
- Prefer specialist sub-agents for specialist work.
- Query `graphify-out/graph.json` before broad repo exploration when it exists.
- Use `bd` for task state, comments, dependencies, and durable memory.
- Check `references/index.md` before broad searches so existing knowledge is reused.
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
| CI, alerting, SLOs, dashboards, observability | `platform-engineer` |
| PR review and CI feedback | `pr-reviewer` |
| Parallel research or general support | `worker` |

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
