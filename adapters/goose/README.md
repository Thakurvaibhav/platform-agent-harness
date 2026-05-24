# Goose Adapter

Goose loads project hints from `.goosehints` in the working directory and global hints from `~/.config/goose/.goosehints`. Recent Goose builds also recognise `AGENTS.md`. See the Goose docs at <https://block.github.io/goose/>.

## File mapping

| Harness source | Destination in your repo | Notes |
| --- | --- | --- |
| `templates/AGENTS.template.md` | `.goosehints` (and optionally `AGENTS.md`) | Primary hints file Goose appends to its system prompt. |
| `core/protocols/safety-and-handoff.md` | append into `.goosehints` | Inline so it's always loaded. |
| `core/protocols/rtk-command-policy.md` | append into `.goosehints` | Same. |
| `core/agents/*.md` | `docs/agents/` | Referenced by link from `.goosehints`. |
| `skills/*/SKILL.md` | `goose recipes` (under `~/.config/goose/recipes/`) or `docs/skills/` | Convert long playbooks to recipes for reuse. |

## Bootstrap

```bash
HARNESS=/path/to/platform-agent-harness
mkdir -p docs/agents docs/skills

cp "$HARNESS/templates/AGENTS.template.md" ./.goosehints
cp "$HARNESS"/core/agents/*.md             docs/agents/
cp -R "$HARNESS"/skills/*                  docs/skills/

cat "$HARNESS/core/protocols/safety-and-handoff.md"  >> .goosehints
cat "$HARNESS/core/protocols/rtk-command-policy.md"  >> .goosehints
```

For a global default:

```bash
mkdir -p ~/.config/goose
cp "$HARNESS/templates/AGENTS.template.md" ~/.config/goose/.goosehints
```

## Recipes

Turn each skill into a Goose recipe so it can be invoked by name. Minimal example for `helm-upgrade`:

```yaml
version: "1.0"
title: helm-upgrade
description: Upgrade a Helm subchart with render-diff and immutable-field checks.
instructions: |
  Follow the playbook in docs/skills/helm-upgrade/SKILL.md.
  Before finishing, run `bd remember` to persist learnings.
```

Save under `~/.config/goose/recipes/helm-upgrade.yaml` and invoke with `goose run --recipe helm-upgrade`.

## Verify

```bash
goose --version
test -f .goosehints
goose session start --no-auto-execute   # then: "Summarize the safety rules from my hints."
```

## Do not commit

- `~/.config/goose/config.yaml` (contains provider tokens)
- Session logs and SQLite databases under `~/.local/share/goose/`
- API keys in `.goosehints`
