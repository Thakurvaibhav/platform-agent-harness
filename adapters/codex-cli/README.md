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

### Sandbox and bd daemon access

The bd hive is backed by a running Dolt SQL daemon on `127.0.0.1:50656`. Under the default `workspace-write` sandbox, Codex workers **cannot** reach it (localhost TCP is blocked, `.beads` FS writes are blocked). Symptoms: `bd prime` silently returns 0 memories; `bd remember` errors "Dolt server unreachable."

**Option A** (full access, recommended for trusted repos):
```toml
sandbox_mode = "danger-full-access"
```

**Option B** (keep sandbox, punch holes for bd):
```toml
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = true
writable_roots = ["<repo>/.beads"]
```

Always smoke-test bd access after changing sandbox config: `codex exec "bd prime --memories-only"`.

### Command denylist (execpolicy) — enforce the deny set even under full access

`danger-full-access` removes the sandbox, so nothing stops a mutating command. Codex has a **separate** enforcement layer — execpolicy — that still applies. Use it to translate [`installation/command-denylist.md`](../../installation/command-denylist.md) into a runtime deny set that hard-blocks dangerous commands regardless of sandbox mode. This is how Codex gets the same **shared safety model** Claude Code has via `permissions.deny` — not just the shared bd hive.

Codex auto-loads `~/.codex/rules/*.rules` at runtime. Add `decision="forbidden"` prefix rules:

```python
# ~/.codex/rules/default.rules  (auto-loaded; forbidden blocks even under danger-full-access)
prefix_rule(pattern=["kubectl", "apply"],  decision="forbidden")
prefix_rule(pattern=["kubectl", "delete"], decision="forbidden")
prefix_rule(pattern=["kubectl", "patch"],  decision="forbidden")
# … the rest of the kubectl mutating verbs (create/replace/edit/scale/rollout/set/
#    annotate/label/taint/cordon/uncordon/drain) from installation/command-denylist.md
prefix_rule(pattern=["helm", "upgrade"],   decision="forbidden")
prefix_rule(pattern=["helm", "install"],   decision="forbidden")
prefix_rule(pattern=["helm", "uninstall"], decision="forbidden")
prefix_rule(pattern=["git", "push", "--force"],            decision="forbidden")
prefix_rule(pattern=["git", "push", "--force-with-lease"], decision="forbidden")
# Reads (kubectl get/describe/logs, helm template/lint) are not matched → allowed.
```

**Validate offline before installing** — no live command runs:

```bash
codex execpolicy check --rules ~/.codex/rules/default.rules kubectl apply -f x.yaml   # -> "forbidden"
codex execpolicy check --rules ~/.codex/rules/default.rules kubectl get pods           # -> no match (allowed)
```

**Limitations (be honest about them):**
- The keyword is `decision="forbidden"` — not `deny`/`reject` (those fail to parse).
- `prefix_rule` matches the **literal argv prefix**, so wrapper forms (`sudo …`, `env X=Y …`, `bash -c "…"`, a read-only wrapper like `rtk …`) are **not** caught. Mirror any wrapper your harness uses idiomatically with its own `<wrapper> kubectl apply` rules; the rest rely on convention.
- A trailing-arg target (e.g. deny push to `main` specifically) is **not** expressible as a prefix — rely on the remote's branch protection for that.

## Hooks

Wire hooks via `~/.codex/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "<path-to>/agent-knowledge/scripts/codex-session-prime.sh"
          }
        ]
      }
    ]
  }
}
```

The SessionStart hook warms the bd hive and surfaces the memory count. Codex hooks **must** emit valid JSON to stdout (the `hookSpecificOutput` contract); plain text triggers "invalid session start JSON output" errors.

**Hook trust:** Editing `hooks.json` triggers one-time interactive re-trust. Headless `codex exec` skips untrusted hooks unless `--dangerously-bypass-hook-trust` is passed. For unattended enforcement, prefer git hooks (post-commit) over Codex trust-gated hooks.

## Dispatch (fan-out and cross-runtime subagents)

Codex has no native subagent type. Use [`agent-knowledge/scripts/codex-dispatch.sh`](../../agent-knowledge/scripts/codex-dispatch.sh) to achieve Claude-style delegation:

```bash
# Single specialist dispatch
codex-dispatch.sh helm-engineer "Bump <chart> to v1.2.0" /path/to/repo

# Parallel fan-out (distinct bd tasks to avoid write races)
codex-dispatch.sh A "taskA" /repo & codex-dispatch.sh B "taskB" /repo & wait
```

The script loads specialist role definitions from `core/agents/<name>.md` (strips YAML frontmatter), prepends the standard hive preamble, and wraps `codex exec --skip-git-repo-check --cd <dir>`.

### Dispatching Codex FROM Claude (cross-runtime review)

Claude can dispatch Codex as an adversarial reviewer for a fresh-model perspective:

```bash
~/.agent-knowledge/scripts/codex-dispatch.sh general-engineer "<review prompt>" <dir> > /tmp/review.log 2>&1 < /dev/null &
```

Key gotchas:
- **stdin MUST be closed** (`< /dev/null`) or `codex exec` hangs printing "Reading additional input from stdin..."
- **`--skip-git-repo-check`** is required for non-git target dirs
- Concurrent workers writing distinct bd keys do NOT race (Dolt serializes writes)
- Tell the worker NOT to `bd remember` if the doc itself IS the artifact

This pattern is used by the `adopt-eval` skill for mandatory cross-model peer review before human handoff.

### MCP server configuration

Add MCP servers via:
```bash
codex mcp add <name> --url <URL>           # HTTP/OAuth
codex mcp add <name> --env K=V -- <cmd>    # stdio
```

## Overlay template

For the global `~/.codex/AGENTS.md`, use [`templates/codex-overlay.template.md`](../../templates/codex-overlay.template.md) instead of the full `AGENTS.template.md`. The overlay references the shared agent core and adds only Codex-specific mechanics (sandbox, manual rtk, `codex exec` fan-out).

## Verify

```bash
codex --help
test -f AGENTS.md && head -1 AGENTS.md
codex exec "bd prime --memories-only"   # verify bd access works
```

In a session, run `/status` (or your version's equivalent) and confirm `AGENTS.md` is in the loaded project documents.

## Do not commit

- `~/.codex/auth.json`
- Codex session logs
- API keys in any form
