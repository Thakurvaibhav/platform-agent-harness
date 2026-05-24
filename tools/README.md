# External Tools

The harness composes four small CLIs into one operating model. None of them are written by this project — each links to its upstream.

| Tool | Role in the harness | Upstream | Per-tool guide |
| --- | --- | --- | --- |
| `bd` (Beads) | Durable task ledger and cross-session memory | <https://github.com/steveyegge/beads> | [`bd/README.md`](bd/README.md) |
| Graphify | Repo knowledge graph for architecture and dependency questions | <https://github.com/safishamsi/graphify> | [`graphify/README.md`](graphify/README.md) |
| `rtk` | Verbose-output compressor that cuts agent token usage 60–90% | <https://github.com/rtk-ai/rtk> | [`rtk/README.md`](rtk/README.md) |
| `gcx` (optional) | Grafana / Grafana Cloud CLI for cross-signal RCA. Ships an `~/.agents/skills` bundle (`gcx skills install --all`). | <https://github.com/grafana/gcx> | [`gcx/README.md`](gcx/README.md) |

Install order for a fresh setup: `bd` first (so `bd prime` works at session start), then `graphify` (so you can build a graph before the first non-trivial task), then `rtk` (so verbose commands stop blowing the context window). Install `gcx` only if you run a Grafana stack — then run `gcx skills install --all` to pull the bundled observability skills instead of vendoring them.

See [`../installation/prerequisites.md`](../installation/prerequisites.md) for the full prerequisite list with one-click install links.
