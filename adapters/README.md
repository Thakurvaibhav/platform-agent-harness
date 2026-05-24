# Runtime Adapters

Each adapter explains how to wire the portable harness into a specific CLI agent runtime — what file to copy where, what frontmatter is required, how to install hooks, and what to verify.

## Where each runtime looks

| Runtime | Primary instruction file | Agents/subagents | Skills/commands | Hooks |
| --- | --- | --- | --- | --- |
| Claude Code | `CLAUDE.md` or `AGENTS.md` | `.claude/agents/` | `.claude/skills/`, `.claude/commands/`, `~/.agents/skills/` | `.claude/hooks/` |
| Codex CLI | `AGENTS.md` (root + nested), `~/.codex/AGENTS.md` | n/a (prompt-routed) | `~/.agents/skills/` (`.agents` convention) | n/a |
| Aider | `CONVENTIONS.md` via `.aider.conf.yml` `read:` | n/a | n/a | n/a |
| Goose | `.goosehints` or `AGENTS.md` | n/a | `goose recipes` | n/a |
| OpenCode | `AGENTS.md` (root), `~/.config/opencode/AGENTS.md` | `.opencode/agent/` | `.opencode/command/`, `~/.agents/skills/` | n/a |
| Factory Droid | `AGENTS.md` (root or `~/.factory/`) | `.factory/droids/` | `.factory/skills/` | `.factory/hooks/` |

`~/.agents/skills/` is the cross-tool [`.agents`](https://github.com/openai/codex/blob/main/docs/agents-spec.md) skill convention. `gcx skills install --all` populates it with the 18-skill Grafana bundle. For runtimes that look elsewhere (e.g. Factory Droid), pass `--dir <path>` to `gcx skills install` or symlink.

## Shared adoption flow

1. Copy [`templates/AGENTS.template.md`](../templates/AGENTS.template.md) into your repo as `AGENTS.md` (or the runtime-specific filename above).
2. Copy the agents you need from [`core/agents/`](../core/agents/) into the runtime's agent directory.
3. Copy the skills you need from [`skills/`](../skills/) into the runtime's skill directory.
4. Copy protocols your workflow depends on from [`core/protocols/`](../core/protocols/).
5. Install hooks from [`core/hooks/`](../core/hooks/) — only if the runtime supports them.
6. Translate [`installation/command-denylist.md`](../installation/command-denylist.md) into the runtime's permission/denylist format.
7. Keep runtime settings, credentials, MCP config, sessions, logs, and local paths uncommitted.

> The root [`AGENTS.md`](../AGENTS.md) in this harness repo describes the harness source repo itself. Do **not** copy it. The file you copy into your repo is [`templates/AGENTS.template.md`](../templates/AGENTS.template.md).

## Adapters

| Runtime | Path |
| --- | --- |
| Aider | [aider/README.md](aider/README.md) |
| Claude Code | [claude-code/README.md](claude-code/README.md) |
| Codex CLI | [codex-cli/README.md](codex-cli/README.md) |
| Factory Droid | [factory-droid/README.md](factory-droid/README.md) |
| Goose | [goose/README.md](goose/README.md) |
| OpenCode | [opencode/README.md](opencode/README.md) |
