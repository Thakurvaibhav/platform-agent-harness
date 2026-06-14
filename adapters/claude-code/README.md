# Claude Code Adapter

Claude Code reads project memory from `CLAUDE.md` (and `AGENTS.md` as a fallback) and discovers subagents, skills, commands, and hooks under `.claude/`. See [memory docs](https://code.claude.com/docs/en/memory), [`.claude` directory docs](https://code.claude.com/docs/en/claude-directory), and [subagents docs](https://code.claude.com/docs/en/sub-agents).

## File mapping

| Harness source | Destination in your repo | Notes |
| --- | --- | --- |
| `templates/AGENTS.template.md` | `CLAUDE.md` (or `AGENTS.md`) | Root memory file. Either name works; `CLAUDE.md` is the native default. |
| `core/agents/<agent>.md` | `.claude/agents/<agent>.md` | One subagent per file. Add YAML frontmatter (`name`, `description`, `tools`) so Claude can route to it. |
| `skills/<skill>/SKILL.md` | `.claude/skills/<skill>/SKILL.md` | Skills are loaded from this directory. |
| `core/protocols/*.md` | `.claude/protocols/*.md` (or `docs/`) | Referenced from `CLAUDE.md`; no auto-loading. |
| `agent-knowledge/` | `~/.agent-knowledge/` (symlink or copy) | Shared knowledge home — references, scripts, metrics. Point `.claude/` at it; see [Knowledge home](#knowledge-home-agent-knowledge). |
| `core/hooks/generic/pre-task-check.sh` | `~/.claude/hooks/pre-task-check.sh` | Portable. Session-start tool/`bd prime` check. |
| `core/hooks/generic/rtk-wrapper.sh` | `~/.claude/hooks/rtk-wrapper.sh` | Portable shell fallback for rtk prefixing (the native `rtk hook claude` is preferred — see [Automatic rtk prefixing](#automatic-rtk-prefixing)). |
| `core/hooks/generic/learning-gate.py` | `~/.claude/hooks/learning-gate.py` | Portable. Learning-capture gate + citation heatmap. Binds to `UserPromptSubmit` + `SubagentStop`. |
| `core/hooks/factory-droid/ctx-threshold-warn.py` | `~/.claude/hooks/ctx-threshold-warn.py` | Authored for Factory but stdlib-only and runtime-portable. `UserPromptSubmit` context-budget nudge. |
| `core/hooks/factory-droid/pre-compact-bd-sync.py` | `~/.claude/hooks/pre-compact-bd-sync.py` | Authored for Factory but stdlib-only and runtime-portable. `PreCompact` bd snapshot. |
| `core/hooks/factory-droid/post-compact-prime-reminder.sh` | `~/.claude/hooks/post-compact-prime-reminder.sh` | Authored for Factory but pure bash and runtime-portable. `SessionStart` `bd prime` reload. |
| `core/statusline/statusline.sh` | `~/.claude/statusline.sh` | Optional statusline (wire under `statusLine`). |
| `core/statusline/statusline-context.py` | `~/.claude/statusline-context.py` | Resolved as a sibling of `statusline.sh`; also used by `ctx-threshold-warn.py`. |
| `installation/command-denylist.md` | `.claude/settings.json` → `permissions.deny` | Translate denylist entries into Claude permission rules (see [`permissions`](#full-claudesettingsjson)). |

> The three `factory-droid/` hooks above were originally authored for Factory Droid, but they are pure stdlib Python / bash with no Factory-only assumptions, so they run unchanged under Claude Code. `learning-gate.py` parses Claude-Code-style JSONL transcripts natively.

`gcx skills install --all` already places observability skills under `~/.agents/skills/`, which Claude Code auto-discovers in addition to `.claude/skills/`.

## Knowledge home (`agent-knowledge/`)

The harness keeps protocols, topic learnings, the knowledge-home scripts, and the citation heatmap in a single shared home, [`agent-knowledge/`](../../agent-knowledge/). Claude Code points **at** this home rather than owning a private copy. Pick one of:

```bash
HARNESS=/path/to/platform-agent-harness

# Option A — symlink the deployed home at the harness source (read-through).
ln -s "$HARNESS/agent-knowledge" ~/.agent-knowledge

# Option B — copy/seed a standalone home you can edit independently.
mkdir -p ~/.agent-knowledge
cp -R "$HARNESS"/agent-knowledge/* ~/.agent-knowledge/
```

Then reference `~/.agent-knowledge/references/` from `CLAUDE.md`, your subagents, and your hooks. The home's scripts and the `learning-gate.py` hook honor these env knobs (default to `~/.agent-knowledge`):

| Env var | Default | Used by |
| --- | --- | --- |
| `HARNESS_REFS` | `~/.agent-knowledge/references` | `knowledge-search.sh`, `drift-check.sh`, `learn.sh` |
| `HARNESS_METRICS` | `~/.agent-knowledge/metrics` | `learning-gate.py` citation heatmap |

## Bootstrap

```bash
HARNESS=/path/to/platform-agent-harness
mkdir -p .claude/agents .claude/skills .claude/protocols ~/.claude/hooks

cp "$HARNESS/templates/AGENTS.template.md" ./CLAUDE.md

for f in "$HARNESS"/core/agents/*.md; do
  cp "$f" ".claude/agents/$(basename "$f")"
done

for d in "$HARNESS"/skills/*/; do
  cp -R "$d" ".claude/skills/"
done

cp "$HARNESS"/core/protocols/*.md .claude/protocols/

# Portable (generic) hooks.
cp "$HARNESS"/core/hooks/generic/pre-task-check.sh  ~/.claude/hooks/
cp "$HARNESS"/core/hooks/generic/rtk-wrapper.sh     ~/.claude/hooks/
cp "$HARNESS"/core/hooks/generic/learning-gate.py   ~/.claude/hooks/

# Runtime-portable hooks authored under factory-droid/ (stdlib Python / bash).
cp "$HARNESS"/core/hooks/factory-droid/ctx-threshold-warn.py        ~/.claude/hooks/
cp "$HARNESS"/core/hooks/factory-droid/pre-compact-bd-sync.py       ~/.claude/hooks/
cp "$HARNESS"/core/hooks/factory-droid/post-compact-prime-reminder.sh ~/.claude/hooks/

# Statusline + its context parser (sibling resolution).
cp "$HARNESS"/core/statusline/statusline.sh         ~/.claude/statusline.sh
cp "$HARNESS"/core/statusline/statusline-context.py ~/.claude/statusline-context.py

chmod +x ~/.claude/hooks/* ~/.claude/statusline.sh 2>/dev/null || true
```

Open `CLAUDE.md` and replace placeholders (repo name, cluster naming, contact owners). `ctx-threshold-warn.py` finds the context parser via `CTX_STATUSLINE_PATH`; export `CTX_STATUSLINE_PATH=~/.claude/statusline-context.py` if it is not on the hook's default search path.

## Subagent frontmatter

```yaml
---
name: helm-engineer
description: Helm chart authoring and upgrades. Use for chart edits and version bumps.
tools: Read, Edit, Bash, Grep, Glob
---
```

## Automatic rtk prefixing

Claude Code can prefix eligible read-only commands with [`rtk`](https://github.com/rtk-ai/rtk) transparently, so agents never type `rtk` manually. Wire the native `rtk hook claude` mechanism under a `PreToolUse` matcher for `Bash` (see [`permissions`](#full-claudesettingsjson)):

```json
"PreToolUse": [
  { "matcher": "Bash", "hooks": [ { "type": "command", "command": "rtk hook claude" } ] }
]
```

`rtk hook claude` reads the tool call on stdin, rewrites the command to its `rtk`-wrapped form when it is on rtk's read-only allowlist, and passes everything else through unchanged. If `rtk` is not installed the matcher is a graceful no-op (the command runs raw). The Factory Droid runtime instead ships the equivalent logic as a Python `PreToolUse` hook, [`core/hooks/factory-droid/rtk-autoprefix.py`](../../core/hooks/factory-droid/rtk-autoprefix.py); the policy both implement is [`core/protocols/rtk-command-policy.md`](../../core/protocols/rtk-command-policy.md). The portable shell fallback [`core/hooks/generic/rtk-wrapper.sh`](../../core/hooks/generic/rtk-wrapper.sh) covers runtimes with neither.

## Full `.claude/settings.json`

A complete, production-shaped wiring. Tilde paths (`~/.claude/...`) keep it machine-independent — adjust hook destinations if you installed elsewhere. Tailor `permissions.allow` to the MCP write tools and read-only commands your team actually uses.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "python3 ~/.claude/hooks/ctx-threshold-warn.py", "timeout": 10 }
        ]
      },
      {
        "hooks": [
          { "type": "command", "command": "python3 ~/.claude/hooks/learning-gate.py", "timeout": 10 }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "rtk hook claude" }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "auto|manual",
        "hooks": [
          { "type": "command", "command": "python3 ~/.claude/hooks/pre-compact-bd-sync.py", "timeout": 30 }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/post-compact-prime-reminder.sh" }
        ]
      },
      {
        "matcher": "compact",
        "hooks": [
          { "type": "command", "command": "~/.claude/hooks/post-compact-prime-reminder.sh" }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          { "type": "command", "command": "python3 ~/.claude/hooks/learning-gate.py", "timeout": 15 }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  },
  "env": {
    "CTX_MAX_TOKENS": "200000"
  },
  "permissions": {
    "deny": [
      "Bash(git push origin main)",
      "Bash(git push origin main:*)",
      "Bash(git push origin master)",
      "Bash(git push origin master:*)",
      "Bash(git push --force origin main)",
      "Bash(git push --force origin master)",
      "Bash(git push --force-with-lease origin main)",
      "Bash(git push --force-with-lease origin master)",
      "Bash(kubectl apply:*)",
      "Bash(kubectl create:*)",
      "Bash(kubectl delete:*)",
      "Bash(kubectl patch:*)",
      "Bash(kubectl replace:*)",
      "Bash(kubectl edit:*)",
      "Bash(kubectl scale:*)",
      "Bash(kubectl rollout:*)",
      "Bash(kubectl set:*)",
      "Bash(kubectl annotate:*)",
      "Bash(kubectl label:*)",
      "Bash(kubectl taint:*)",
      "Bash(kubectl cordon:*)",
      "Bash(kubectl uncordon:*)",
      "Bash(kubectl drain:*)",
      "Bash(helm install:*)",
      "Bash(helm upgrade:*)",
      "Bash(helm uninstall:*)",
      "Bash(helm rollback:*)",
      "Bash(helm delete:*)",
      "Bash(bd edit:*)"
    ],
    "allow": [
      "Read",
      "Grep",
      "Glob",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Bash(bd *:*)",
      "mcp__<server>__<writeTool1>",
      "mcp__<server>__<writeTool2>"
    ]
  }
}
```

Notes:

- `UserPromptSubmit` runs the context-budget nudge and the learning-capture soft nudge; `SubagentStop` runs the learning-capture hard gate. Both reuse the same `learning-gate.py`.
- `PreCompact` matcher `auto|manual` snapshots bd memory before either compaction path. `SessionStart` matchers `startup` and `compact` reload `bd prime`.
- `env.CTX_MAX_TOKENS` is an example; set it to your model's effective compaction limit. Add other env (e.g. `BEADS_DB`, `HARNESS_REFS`, `HARNESS_METRICS`) here as needed.
- `permissions.deny` is the full mutating-command denylist; keep it in sync with [`installation/command-denylist.md`](../../installation/command-denylist.md).
- `permissions.allow` is a short example. Adopters tailor it to the read-only commands and MCP write tools their workflows require — the two `mcp__<server>__<writeTool>` entries are placeholders for whichever MCP write tools you pre-approve.

## Verify

```bash
ls .claude/agents .claude/skills .claude/protocols ~/.claude/hooks
python3 -c "import json; json.load(open('.claude/settings.json'))" && echo "settings.json OK"
claude --version
```

In a Claude session, ask: "List the subagents you can see." Confirm it enumerates the files in `.claude/agents/`.

## Do not commit

- `.claude/settings.local.json`
- OAuth and credential files
- Real `graphify-out/`
- Real `.beads/`
