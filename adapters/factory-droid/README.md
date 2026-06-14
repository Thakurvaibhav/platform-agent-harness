# Factory Droid Adapter

Factory Droid reads agent rules from `AGENTS.md` (project root and `~/.factory/AGENTS.md`), discovers custom droids in `.factory/droids/`, skills in `.factory/skills/`, and hooks in `.factory/hooks/`.

## File mapping

| Harness source | Destination in your repo | Notes |
| --- | --- | --- |
| `templates/AGENTS.template.md` | `AGENTS.md` (repo root) or `~/.factory/AGENTS.md` | Primary rules file. Use the global path to apply across every project. |
| `core/agents/<agent>.md` | `.factory/droids/<agent>.md` or `~/.factory/droids/<agent>.md` | One droid per file. Match the frontmatter your version expects. |
| `skills/<skill>/SKILL.md` | `.factory/skills/<skill>/SKILL.md` or `~/.factory/skills/<skill>/SKILL.md` | Skills auto-discovered from these locations. |
| `core/hooks/factory-droid/*.{py,sh}` | `.factory/hooks/<event>/` | Wire under `SessionStart`, `PreToolUse`, `PreCompact`, etc. |
| `core/hooks/generic/learning-gate.py` | `.factory/hooks/<event>/learning-gate.py` | Portable learning-capture gate + citation heatmap. Bind to the `SubagentStop` + `UserPromptSubmit` equivalents (see [Learning-capture gate](#learning-capture-gate)). |
| `agent-knowledge/` | `~/.agent-knowledge/` (referenced via symlinks) | Shared knowledge home; Factory's `references/` and `scripts/` paths symlink into it (see [Knowledge home](#knowledge-home-agent-knowledge)). |
| `core/statusline/statusline.sh` | `.factory/statusline.sh` | Optional statusline. |
| `core/statusline/statusline-context.py` | `.factory/statusline-context.py` | Used by `ctx-threshold-warn.py` for accurate context utilization. |
| `installation/command-denylist.md` | `.factory/settings.json` → `commandDenylist` | Translate denylist into runtime config. |

## Knowledge home (`agent-knowledge/`)

Factory reaches the shared [`agent-knowledge/`](../../agent-knowledge/) home through **symlinks**, so its historical paths keep working unchanged — this is the real deployment shape:

```bash
# Deployed home (symlink at the harness source, or a copied standalone home).
ln -s /path/to/platform-agent-harness/agent-knowledge ~/.agent-knowledge

# Point Factory's historical paths at the home.
ln -s ~/.agent-knowledge/references ~/.factory/droids/references
ln -s ~/.agent-knowledge/scripts    ~/.factory/scripts
```

The home's scripts and `learning-gate.py` honor `HARNESS_REFS` (default `~/.agent-knowledge/references`) and `HARNESS_METRICS` (default `~/.agent-knowledge/metrics`). See [`agent-knowledge/README.md`](../../agent-knowledge/README.md).

## Learning-capture gate

[`core/hooks/generic/learning-gate.py`](../../core/hooks/generic/learning-gate.py) is portable and runs under Factory like the other Python hooks. Bind it to two events:

| Factory event | Behavior | Claude-Code equivalent |
| --- | --- | --- |
| `SubagentStop` | Hard gate — blocks a sub-agent's stop once if it did substantive work but persisted no learning. | `SubagentStop` |
| `UserPromptSubmit` | Soft, debounced nudge for the long-lived main session. | `UserPromptSubmit` |

If your Factory build names these events differently, map them to the closest stop / prompt-submit equivalents. The gate parses Claude-Code-style JSONL transcripts; under a runtime whose transcript shape differs, the `parse_transcript` function may need a small per-runtime tweak (the hook's file header documents this). It writes the citation heatmap to `${HARNESS_METRICS:-~/.agent-knowledge/metrics}`. Env switches: `LEARN_GATE_DISABLE`, `LEARN_METRICS_DISABLE`, `LEARN_TOOLUSE_MIN`, `LEARN_MAIN_GAP`.

The existing `rtk-autoprefix.py` (`PreToolUse`), `pre-compact-bd-sync.py` (`PreCompact`), `ctx-threshold-warn.py` (`UserPromptSubmit`), and `post-compact-prime-reminder.sh` (`SessionStart`) wiring is unchanged.

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
cp    "$HARNESS"/core/hooks/generic/learning-gate.py .factory/hooks/
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
