---
name: graphify
description: >-
  Build and query a repository knowledge graph for architecture and dependency
  questions. Use when the user asks how something connects, where something is
  implemented, or any question that would otherwise require reading many files.
---

# Graphify

Turn any folder of code, docs, papers, or images into a queryable knowledge graph. Querying a graph typically costs ~70x fewer tokens than file-by-file reading.

Upstream: <https://github.com/safishamsi/graphify>

## When to use

- Architecture questions: "How does X connect to Y?"
- Dependency tracing: "Which charts reference this Service?"
- God-node detection: "Which file has the most incoming edges?"
- Migration planning: "What breaks if I rename this CRD?"

## Build a graph

```bash
cd <repo>
graphify . --no-viz
```

Output lands in `graphify-out/`. The harness `.gitignore` excludes this directory — never commit a real private-repo graph.

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

Use results to select the **smallest set of files** to actually read. The graph guides exploration; source files remain the final authority.

## Pattern: graphify-first, source-of-truth-second

1. Read the user's question.
2. If `graphify-out/graph.json` exists, query it.
3. From the result set, pick the 3–10 most relevant files.
4. Read those files (not the entire directory).
5. Answer with citations to the actual files — not to graph nodes.

## When to rebuild

- Significant repo restructuring.
- New chart / module added.
- Renames of frequently referenced symbols.

Otherwise, the existing graph is usually good enough for weeks.

## Safety

- Never publish a real private-repo graph or `GRAPH_REPORT.md`.
- For public examples, use a sanitized sample graph or commit only `graphify-out/.gitkeep`.

## Memory

```bash
bd remember "graphify build for <repo>: <god nodes / community summary>" --key <repo>/tool/graphify
```
