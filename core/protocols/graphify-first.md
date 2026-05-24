# Graphify-First Exploration

[Graphify](https://github.com/safishamsi/graphify) turns any folder of code, docs, papers, or images into a queryable knowledge graph. The harness uses it to answer architecture and dependency questions **before** linear file reads.

## When to query the graph

- Architecture questions ("how does deployment config flow to workloads?").
- Cross-module dependency tracing.
- "What connects X to Y?" questions.
- Finding god nodes and surprising connections that grep would miss.

## Workflow

When `graphify-out/graph.json` exists in a repo:

```bash
graphify query "How does deployment config flow to workloads?"
graphify path "HelmChart" "ArgoCDApplication"
graphify explain "ServiceAccount"
```

Use graph results to choose the **smallest set of files** to actually read. Verify against source before editing.

If `graphify-out/graph.json` does not exist, build one:

```bash
cd <repo>
graphify . --no-viz
```

Check `graphify-out/GRAPH_REPORT.md` for god nodes and a community-detection summary.

## Token economics

Architecture questions answered via Graphify typically cost ~70x fewer tokens than file-by-file reading. The one-time graph build is expensive; querying is nearly free.

## Boundaries

- The graph guides exploration; **source files remain the final authority.**
- Never publish a real private-repo graph. Use only sanitized example graphs in public examples.
- `graphify-out/` is in the harness `.gitignore` for this reason.

## Skill

The full build + query workflow is encoded as a skill: [`skills/graphify/SKILL.md`](../../skills/graphify/SKILL.md). Invoke it whenever the user asks an architecture question and a graph exists or could exist.
