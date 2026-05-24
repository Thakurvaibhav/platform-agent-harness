# Graphify

Graphify turns any folder of code, docs, papers, or images into a queryable knowledge graph. The harness uses it for graph-first exploration: agents query the graph for architecture questions and dependency tracing before reading files one by one.

- Upstream repo: <https://github.com/safishamsi/graphify>
- Project site: <https://graphify.net/>

## Why the harness uses it

- **One-time cost, repeated value.** Building a graph is expensive; querying it is nearly free in tokens.
- **Architecture-first answers.** Questions like "what connects X to Y?" or "which files implement auth?" resolve in seconds without linear file reads.
- **Cross-file insight.** Community detection surfaces god nodes and surprising connections traditional grep misses.

## Install

Follow the [Graphify installation instructions](https://github.com/safishamsi/graphify#installation) for your platform. Typical install:

```bash
pipx install graphify
```

Verify:

```bash
graphify --help
```

## Build a graph

```bash
cd <your-repo>
graphify . --no-viz
```

Output lands in `graphify-out/` (already in this harness's `.gitignore` — never commit a real graph from a private repo).

Inspect the build report for god nodes and surprising connections:

```bash
cat graphify-out/GRAPH_REPORT.md
```

## Query

```bash
graphify query "How does deployment config flow to workloads?"
graphify path "HelmChart" "ArgoCDApplication"
graphify explain "ServiceAccount"
```

## Harness rules

- Run `graphify query` before broad file reads when `graphify-out/graph.json` exists.
- Use graph results to choose the smallest file set to read.
- Always verify against source before editing — the graph guides exploration, source is the authority.
- Never publish a real private-repo graph. Use sanitized example graphs in public examples.

See [`core/protocols/graphify-first.md`](../../core/protocols/graphify-first.md) and [`skills/graphify/SKILL.md`](../../skills/graphify/SKILL.md) for the full workflow.
