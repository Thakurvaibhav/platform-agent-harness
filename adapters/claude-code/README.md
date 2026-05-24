# Claude Code Adapter

Claude Code reads project memory from `CLAUDE.md` (and `AGENTS.md` as a fallback) and discovers subagents, skills, commands, and hooks under `.claude/`. See [memory docs](https://code.claude.com/docs/en/memory), [`.claude` directory docs](https://code.claude.com/docs/en/claude-directory), and [subagents docs](https://code.claude.com/docs/en/sub-agents).

## File mapping

| Harness source | Destination in your repo | Notes |
| --- | --- | --- |
| `templates/AGENTS.template.md` | `CLAUDE.md` (or `AGENTS.md`) | Root memory file. Either name works; `CLAUDE.md` is the native default. |
| `core/agents/<agent>.md` | `.claude/agents/<agent>.md` | One subagent per file. Add YAML frontmatter (`name`, `description`, `tools`) so Claude can route to it. |
| `skills/<skill>/SKILL.md` | `.claude/skills/<skill>/SKILL.md` | Skills are loaded from this directory. |
| `core/protocols/*.md` | `.claude/protocols/*.md` (or `docs/`) | Referenced from `CLAUDE.md`; no auto-loading. |
| `core/hooks/generic/*.sh` | `.claude/hooks/<event>/*.sh` | Wire under PreToolUse / PostToolUse / SessionStart / PreCompact events. |
| `installation/command-denylist.md` | `.claude/settings.json` → `permissions.deny` | Translate denylist entries into Claude permission rules. |

`gcx skills install --all` already places observability skills under `~/.agents/skills/`, which Claude Code auto-discovers in addition to `.claude/skills/`.

## Bootstrap

```bash
HARNESS=/path/to/platform-agent-harness
mkdir -p .claude/agents .claude/skills .claude/protocols .claude/hooks/pre-tool-use .claude/hooks/session-start .claude/hooks/pre-compact

cp "$HARNESS/templates/AGENTS.template.md" ./CLAUDE.md

for f in "$HARNESS"/core/agents/*.md; do
  cp "$f" ".claude/agents/$(basename "$f")"
done

for d in "$HARNESS"/skills/*/; do
  cp -R "$d" ".claude/skills/"
done

cp "$HARNESS"/core/protocols/*.md .claude/protocols/
cp "$HARNESS"/core/hooks/generic/pre-task-check.sh   .claude/hooks/session-start/
cp "$HARNESS"/core/hooks/generic/rtk-wrapper.sh      .claude/hooks/pre-tool-use/
cp "$HARNESS"/core/hooks/factory-droid/pre-compact-bd-sync.py .claude/hooks/pre-compact/

chmod +x .claude/hooks/*/*.sh .claude/hooks/*/*.py 2>/dev/null || true
```

Open `CLAUDE.md` and replace placeholders (repo name, cluster naming, contact owners).

## Subagent frontmatter

```yaml
---
name: helm-engineer
description: Helm chart authoring and upgrades. Use for chart edits and version bumps.
tools: Read, Edit, Bash, Grep, Glob
---
```

## Minimal `.claude/settings.json`

```json
{
  "permissions": {
    "allow": ["Read", "Grep", "Glob", "Bash(git status:*)", "Bash(bd *:*)"],
    "deny":  ["Bash(kubectl apply:*)", "Bash(helm upgrade:*)", "Bash(git push --force:*)"]
  }
}
```

Populate `deny` from [`installation/command-denylist.md`](../../installation/command-denylist.md).

## Verify

```bash
ls .claude/agents .claude/skills .claude/protocols .claude/hooks
claude --version
```

In a Claude session, ask: "List the subagents you can see." Confirm it enumerates the files in `.claude/agents/`.

## Do not commit

- `.claude/settings.local.json`
- OAuth and credential files
- Real `graphify-out/`
- Real `.beads/`
