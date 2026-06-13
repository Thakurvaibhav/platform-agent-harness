# Harness Pillars

The harness is more than a prompt library. Its differentiation comes from combining specialist execution, durable state, indexed knowledge, graph context, and validation into one operating model.

## 1. Specialist sub-agents

Each agent encodes a domain contract:

- `task-planner` decomposes and sequences work; doesn't write code.
- `tool-researcher` evaluates tools before implementation; doesn't create manifests.
- `helm-engineer` owns chart and values work.
- `argocd-engineer` owns GitOps application and rollout config.
- `platform-engineer` owns CI, observability, alerting, and SLOs.
- `pr-reviewer` provides a second pass before human review.
- `general-engineer` handles bounded parallel research, code exploration, and general-purpose engineering.

The `contract-validation` skill covers feature, surface, and milestone validation without needing a dedicated validator agent. This lets the harness behave like a small platform team instead of one generic assistant.

## 2. bd task and memory substrate

`bd` (Beads) provides durable state outside the model context:

- Task claiming, dependencies, comments, ready queues.
- Persistent memories that survive compaction.
- Retrospective learnings keyed by domain.

Hooks make the loop automatic — see [`LIFECYCLE.md`](../../LIFECYCLE.md).

## 3. Indexed knowledge base (Karpathy LLM Wiki pattern)

A hand-curated, markdown-only local knowledge base that agents read **before** they grep the repo. Three pieces:

- [`agent-knowledge/references/index.md`](../../agent-knowledge/references/index.md) — master catalog, one row per doc.
- [`agent-knowledge/references/log.md`](../../agent-knowledge/references/log.md) — append-only chronology of non-trivial work.
- `agent-knowledge/references/learnings-*.md` — numbered, append-only learnings per domain. Each item is self-contained.

This is a direct adaptation of [Andrej Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f): for a hand-curated corpus, plain markdown the LLM reads on demand outperforms a vector-DB RAG pipeline on precision and maintainability. The harness applies that bet to multi-agent platform engineering and pairs it with `bd remember` for memories generated *during* sessions (the firehose) versus `learnings-*.md` (the curated stream future sessions read first).

The knowledge system also covers:

- Domain packs ([`domain-packs/`](../../domain-packs/)) — focused, reusable patterns.
- Templates ([`templates/`](../../templates/)) — drop-in starting points.
- Examples ([`examples/`](../../examples/)) — worked end-to-end stories.

Full operating rules, promotion path from `bd remember` to numbered learnings, and rationale live in [`agent-knowledge/references/README.md`](../../agent-knowledge/references/README.md). This prevents agents from rediscovering known patterns or missing existing playbooks.

## 4. Graphify-first exploration

[Graphify](https://github.com/safishamsi/graphify) turns repos and corpora into persistent knowledge graphs. Agents use it to:

- Answer architecture questions.
- Trace dependencies.
- Find relevant files.
- Avoid linear repo reads.

Graph output guides exploration; source files remain the final authority. See [`graphify-first.md`](graphify-first.md).

## 5. Skills as executable playbooks

Skills are repeatable operational workflows:

- shiny-engineer — structured Design → Implement → Review → Test → Submit formula with rule-of-five expansion on implementation
- create-pr — consistent PR open flow with structured description, ticket link, CI follow-through
- helm-upgrade — full subchart upgrade flow with render-diff and immutable-field checks
- k8s-debug — read-only Kubernetes triage workflow
- graphify — knowledge-graph build and query workflow
- contract-validation — runnable pass/fail assertion contracts with evidence

Plus the 18-skill Grafana observability bundle installed via `gcx skills install --all`.

Skills turn hard-won process into reusable procedure.

## 6. Safety and validation gates

The harness defaults to safe behavior:

- No mutating Kubernetes commands by default.
- No protected-branch pushes; no force-push to protected branches.
- Worktree isolation for concurrent work.
- Secret review and `trufflehog` / `gitleaks` gates before public sharing.
- Post-deploy validation built into the platform-engineer pre-completion checklist.
- Second-agent PR review for risky changes ([`pr-review-loop.md`](pr-review-loop.md)).

## 7. Token economics

The harness treats context as a scarce resource:

- Native tools for file reads / searches (no shell).
- Graphify to choose files instead of grep-by-glob.
- `rtk` for verbose read-only shell output (60–90% compression).
- Structured, concise handoffs.

Good token economics makes agents faster, cheaper, and less error-prone.

## Adoption checklist

1. Add `AGENTS.md` (copied from [`templates/AGENTS.template.md`](../../templates/AGENTS.template.md)) to the target repo.
2. Install `bd`, Graphify, and `rtk` (see [`installation/prerequisites.md`](../../installation/prerequisites.md)).
3. Build or refresh `graphify-out/graph.json`.
4. Add the relevant sub-agent prompts and skills.
5. Create a reference index and at least one `learnings-*.md` file.
6. Use `bd remember` for reusable learnings from day one.
7. Run [`sanitization/prepublish-checklist.md`](../../sanitization/prepublish-checklist.md) before publishing any derivative.
