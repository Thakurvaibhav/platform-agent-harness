# bd / Beads

`bd` is a git-backed issue tracker designed for AI-supervised coding workflows. The harness uses it as the durable task ledger and the memory substrate that survives context resets and compactions.

- Upstream repo: <https://github.com/steveyegge/beads>
- Documentation: <https://steveyegge.github.io/beads/>

## Why the harness uses it

- **Durable state outside the model.** Tasks, dependencies, comments, and ready-queues persist across sessions.
- **Memory that survives compaction.** `bd remember` writes self-contained insights agents can recall on the next `bd prime`.
- **Multi-agent handoff.** Specialist sub-agents claim, comment on, and close tasks without a shared chat history.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
```

For macOS / Linux package managers, build-from-source, or air-gapped installs, see the [Beads README](https://github.com/steveyegge/beads#install).

Verify:

```bash
bd --version
```

## Initialize in a repo

```bash
cd <your-repo>
bd init --prefix <repo>
bd prime
```

`bd prime` is the canonical session-start hook for the harness. Wire it into your runtime's session-start hook so every agent run begins with workflow context, ready tasks, and recent memories already loaded.

## Core workflow

```bash
bd create "<task title>" -t task -d "<description> [Ticket: <ID>]"
bd ready
bd update <id> --claim
bd comments add <id> "<status>"
bd remember "<learning>" --key <repo>/<prefix>/<topic>
bd close <id> --reason "<reason>"
```

Avoid `bd edit` — it opens `$EDITOR` and blocks non-interactive agents. Use `bd update <id> --title/--description/--notes` instead.

## Memory conventions

Use self-contained memory text and consistent keys. The full taxonomy lives in [`core/protocols/bd-and-memory.md`](../../core/protocols/bd-and-memory.md).

| Prefix | Use for |
| --- | --- |
| `<repo>/decision/<topic>` | Architectural choices and rationale |
| `<repo>/trouble/<topic>` | Resolved issues with root cause and fix |
| `<repo>/tool/<topic>` | Tool research outcomes and version notes |
| `<repo>/lesson/<topic>` | Post-incident or post-task learnings |
| `<repo>/security/<topic>` | Security findings and CVE notes |
| `<repo>/perf/<topic>` | Performance findings and benchmarks |
| `<repo>/pref/<topic>` | User preferences and workflow conventions |

## Lifecycle integration

The whole `bd` story — pre-compact snapshot, in-progress task comments, post-compact prime — is in [`LIFECYCLE.md`](../../LIFECYCLE.md).
