# OpenCode Adapter

OpenCode reads project rules from `AGENTS.md` at the repo root and global rules from `~/.config/opencode/AGENTS.md`. Agents are configured in `opencode.json` or as markdown files in `.opencode/agent/`, and custom commands live in `.opencode/command/`. See [Rules](https://opencode.ai/docs/rules/), [Agents](https://opencode.ai/docs/agents/), [Commands](https://opencode.ai/docs/commands/).

## File mapping

| Harness source | Destination in your repo | Notes |
| --- | --- | --- |
| `templates/AGENTS.template.md` | `AGENTS.md` (repo root) | Primary rules file OpenCode auto-loads. |
| `core/agents/<agent>.md` | `.opencode/agent/<agent>.md` | One agent per file. Add frontmatter (`description`, `mode`, `tools`). |
| `skills/<skill>/SKILL.md` | `.opencode/command/<skill>.md` | Reuse skills as named commands. |
| `core/protocols/*.md` | `docs/protocols/` | Link from `AGENTS.md`. |
| `installation/command-denylist.md` | `opencode.json` → `permission` block | Translate denylist entries into OpenCode permissions. |

`gcx skills install --all` places observability skills under `~/.agents/skills/`, which OpenCode auto-discovers.

## Bootstrap

```bash
HARNESS=/path/to/platform-agent-harness
mkdir -p .opencode/agent .opencode/command docs/protocols

cp "$HARNESS/templates/AGENTS.template.md" ./AGENTS.md

for f in "$HARNESS"/core/agents/*.md; do
  cp "$f" ".opencode/agent/$(basename "$f")"
done

for d in "$HARNESS"/skills/*/; do
  name=$(basename "$d")
  cp "$d/SKILL.md" ".opencode/command/${name}.md"
done

cp "$HARNESS"/core/protocols/*.md docs/protocols/
```

## Agent frontmatter

```yaml
---
description: Helm chart authoring and upgrades. Use for chart edits and version bumps.
mode: subagent
tools:
  read: true
  edit: true
  bash: true
---
```

## opencode.json

```json
{
  "$schema": "https://opencode.ai/config.json",
  "agent": {
    "build": {
      "instructions": ["AGENTS.md", "docs/protocols/safety-and-handoff.md"]
    }
  },
  "permission": {
    "bash": {
      "kubectl apply *": "deny",
      "helm upgrade *":  "deny",
      "git push --force *": "deny"
    }
  }
}
```

Populate `permission.bash` from [`installation/command-denylist.md`](../../installation/command-denylist.md).

## Global rules

```bash
mkdir -p ~/.config/opencode
cp "$HARNESS/templates/AGENTS.template.md" ~/.config/opencode/AGENTS.md
```

## Verify

```bash
opencode --version
test -f AGENTS.md
ls .opencode/agent .opencode/command
```

In a session, run `/agents` and confirm the harness agents are listed.

## Do not commit

- `~/.local/share/opencode/`
- Provider auth tokens
- Session logs
