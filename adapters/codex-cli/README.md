# Codex CLI Adapter

Codex CLI reads project instructions from `AGENTS.md` at the repo root and walks up the directory tree to combine nested files. Global instructions live at `~/.codex/AGENTS.md`. See [Custom instructions with AGENTS.md](https://developers.openai.com/codex/guides/agents-md), [Configuration reference](https://developers.openai.com/codex/config-reference), and [CLI reference](https://developers.openai.com/codex/cli/reference).

## File mapping

| Harness source | Destination in your repo | Notes |
| --- | --- | --- |
| `templates/AGENTS.template.md` | `AGENTS.md` (repo root) | Primary instruction file Codex auto-loads. |
| `core/agents/*.md` | `docs/agents/` (or `agents/`) | Reference by relative link from `AGENTS.md`. Codex routes by prompt, not by file. |
| `skills/*/SKILL.md` | `docs/skills/` (or `skills/`) | Linked from `AGENTS.md`. |
| `core/protocols/*.md` | `docs/protocols/` | Link the canonical operating model from `AGENTS.md`. |
| Subtree-specific overrides | `<subdir>/AGENTS.md` | Codex merges nested `AGENTS.md` files. Use for per-component policy. |

`gcx skills install --all` places observability skills under `~/.agents/skills/` (the `.agents` convention Codex CLI follows).

## Bootstrap

```bash
HARNESS=/path/to/platform-agent-harness
mkdir -p docs/agents docs/skills docs/protocols

cp "$HARNESS/templates/AGENTS.template.md" ./AGENTS.md
cp "$HARNESS"/core/agents/*.md      docs/agents/
cp -R "$HARNESS"/skills/*           docs/skills/
cp "$HARNESS"/core/protocols/*.md   docs/protocols/
```

Edit `AGENTS.md` so each delegation row links to the corresponding file under `docs/agents/`, and the harness pillars link points at `docs/protocols/harness-pillars.md`.

## Global instructions

```bash
mkdir -p ~/.codex
cp "$HARNESS/templates/AGENTS.template.md" ~/.codex/AGENTS.md
```

Use `~/.codex/AGENTS.md` for cross-project rules. Per-repo `AGENTS.md` overrides only when content actually differs.

## Config

`~/.codex/config.toml`:

```toml
model         = "gpt-5-codex"
sandbox_mode  = "workspace-write"

[project_doc]
max_bytes = 65536
```

Raise `max_bytes` if your `AGENTS.md` plus nested files exceed the default budget.

## Verify

```bash
codex --help
test -f AGENTS.md && head -1 AGENTS.md
```

In a session, run `/status` (or your version's equivalent) and confirm `AGENTS.md` is in the loaded project documents.

## Do not commit

- `~/.codex/auth.json`
- Codex session logs
- API keys in any form
