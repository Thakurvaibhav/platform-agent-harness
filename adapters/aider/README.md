# Aider Adapter

Aider loads convention files via the `read:` list in `.aider.conf.yml` (project or `~/.aider.conf.yml` for global). See [YAML config](https://aider.chat/docs/config/aider_conf.html) and [Specifying coding conventions](https://aider.chat/docs/usage/conventions.html). Aider has no native subagent or skill concept; the harness is layered in as conventions plus shell workflow (`bd`, `graphify`, `rtk`).

## File mapping

| Harness source | Destination in your repo | Notes |
| --- | --- | --- |
| `templates/AGENTS.template.md` | `CONVENTIONS.md` | Primary conventions file, listed under `read:`. |
| `core/protocols/harness-pillars.md` | `docs/harness-pillars.md` | Linked from `CONVENTIONS.md`; optionally also under `read:`. |
| `core/protocols/safety-and-handoff.md` | `docs/safety-and-handoff.md` | Add to `read:`. |
| `core/protocols/rtk-command-policy.md` | `docs/rtk-command-policy.md` | Add to `read:`. |
| `core/agents/*.md` | `docs/agents/` | Referenced by link from `CONVENTIONS.md`. |
| `skills/*/SKILL.md` | `docs/skills/` | Referenced playbooks. |

Keep the `read:` list focused — Aider re-sends the full content of every `read:` file each turn.

## Bootstrap

```bash
HARNESS=/path/to/platform-agent-harness
mkdir -p docs/agents docs/skills docs

cp "$HARNESS/templates/AGENTS.template.md"                ./CONVENTIONS.md
cp "$HARNESS"/core/protocols/harness-pillars.md           docs/harness-pillars.md
cp "$HARNESS"/core/protocols/safety-and-handoff.md        docs/safety-and-handoff.md
cp "$HARNESS"/core/protocols/rtk-command-policy.md        docs/rtk-command-policy.md
cp "$HARNESS"/core/agents/*.md                            docs/agents/
cp -R "$HARNESS"/skills/*                                 docs/skills/

cat > .aider.conf.yml <<'YAML'
read:
  - CONVENTIONS.md
  - docs/harness-pillars.md
  - docs/safety-and-handoff.md
  - docs/rtk-command-policy.md
auto-commits: false
dirty-commits: false
YAML
```

## Workflow

- Run `bd prime` before invoking Aider on a non-trivial task.
- Build or refresh the repo graph with `graphify <repo> --no-viz` before broad explorations.
- Wrap simple read-only verbose shell commands you ask Aider to run with `rtk`.
- Use `/run` inside Aider for read-only diagnostics; keep mutating commands raw and explicit.

## Verify

```bash
aider --version
test -f CONVENTIONS.md && test -f .aider.conf.yml
aider --no-auto-commits --read CONVENTIONS.md --message "List the safety rules from my conventions."
```

The reply should enumerate the safety rules section.

## Do not commit

- `.aider.input.history`
- `.aider.chat.history.md`
- `.aider.llm.history`
- API keys (use `~/.aider.conf.yml` or env vars)
