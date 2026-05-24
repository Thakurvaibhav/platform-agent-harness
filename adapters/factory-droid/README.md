# Factory Droid Adapter

Factory Droid reads agent rules from `AGENTS.md` (project root and `~/.factory/AGENTS.md`), discovers custom droids in `.factory/droids/`, skills in `.factory/skills/`, and hooks in `.factory/hooks/`.

## File mapping

| Harness source | Destination in your repo | Notes |
| --- | --- | --- |
| `templates/AGENTS.template.md` | `AGENTS.md` (repo root) or `~/.factory/AGENTS.md` | Primary rules file. Use the global path to apply across every project. |
| `core/agents/<agent>.md` | `.factory/droids/<agent>.md` or `~/.factory/droids/<agent>.md` | One droid per file. Match the frontmatter your version expects. |
| `skills/<skill>/SKILL.md` | `.factory/skills/<skill>/SKILL.md` or `~/.factory/skills/<skill>/SKILL.md` | Skills auto-discovered from these locations. |
| `core/hooks/factory-droid/*.{py,sh}` | `.factory/hooks/<event>/` | Wire under `SessionStart`, `PreToolUse`, `PreCompact`, etc. |
| `core/statusline/statusline.sh` | `.factory/statusline.sh` | Optional statusline. |
| `core/statusline/statusline-context.py` | `.factory/statusline-context.py` | Used by `ctx-threshold-warn.py` for accurate context utilization. |
| `installation/command-denylist.md` | `.factory/settings.json` → `commandDenylist` | Translate denylist into runtime config. |

## Bootstrap (project-local)

```bash
HARNESS=/path/to/platform-agent-harness
mkdir -p .factory/droids .factory/skills .factory/hooks

cp "$HARNESS/templates/AGENTS.template.md" ./AGENTS.md
cp "$HARNESS"/core/agents/*.md             .factory/droids/

for d in "$HARNESS"/skills/*/; do
  cp -R "$d" .factory/skills/
done

cp -R "$HARNESS"/core/hooks/factory-droid/* .factory/hooks/
cp "$HARNESS"/core/statusline/statusline.sh         .factory/statusline.sh
cp "$HARNESS"/core/statusline/statusline-context.py .factory/statusline-context.py
chmod +x .factory/statusline.sh .factory/hooks/*/* 2>/dev/null || true
```

For the gcx skill bundle, install with `--dir .factory/skills` to land them where Droid looks:

```bash
gcx skills install --all --dir .factory/skills
```

## Bootstrap (global)

```bash
mkdir -p ~/.factory/droids ~/.factory/skills

cp "$HARNESS/templates/AGENTS.template.md" ~/.factory/AGENTS.md
cp "$HARNESS"/core/agents/*.md             ~/.factory/droids/

for d in "$HARNESS"/skills/*/; do
  cp -R "$d" ~/.factory/skills/
done

cp "$HARNESS"/core/statusline/statusline-context.py ~/.factory/statusline-context.py
```

## Verify

```bash
droid --version
test -f AGENTS.md
ls ~/.factory/droids ~/.factory/skills 2>/dev/null || ls .factory/droids .factory/skills
```

In a session, ask "List the custom droids you can see." Confirm it enumerates the files in `.factory/droids/`.

## Do not commit

- Raw runtime settings JSON
- Raw MCP configuration JSON
- OAuth files
- Sessions, history, logs
- `.factory/cache/`, `.factory/state/`
