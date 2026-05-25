# Platform Agent Harness

**Turn a CLI coding agent into a coordinated platform engineering teammate.**

A portable, runtime-neutral operating system for AI agents doing Kubernetes, Helm, ArgoCD, CI, and observability work. Works with [Aider](https://aider.chat/), [Claude Code](https://code.claude.com/), [Codex CLI](https://developers.openai.com/codex/cli), [Factory Droid](https://factory.ai/), [Goose](https://block.github.io/goose/), [OpenCode](https://opencode.ai/), or any CLI agent that can read instructions and run shell commands.

> Most agent setups stop at "give it a system prompt." That falls apart on real infra work — multi-step rollouts, second opinions on risky PRs, memory that survives context resets, safe Kubernetes defaults, and parallel investigation across clusters. This harness adds the **operating system around the prompt.**

---

| **Why it pays off** |
| :--- |
| **~70x fewer tokens** for architecture questions via [Graphify](https://github.com/safishamsi/graphify) graph queries vs. linear file reads. |
| **60–90% token compression** on verbose CLI output via [`rtk`](https://github.com/rtk-ai/rtk) with zero workflow change. |
| **Cross-session memory** via [`bd`](https://github.com/steveyegge/beads) — task state, comments, and durable learnings survive every compaction. |
| **Hand-curated knowledge base** ([`references/`](references/)) — markdown-only `index.md`, `log.md`, and numbered `learnings-*.md` agents read before they grep the repo. Adapted from [Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f). |
| **3x+ wall-clock speedup** on N-cluster validation via parallel sub-agent dispatch ([`core/protocols/parallel-dispatch.md`](core/protocols/parallel-dispatch.md)). |
| **Second-agent PR review** with structured bot-reply protocol ([`core/protocols/pr-review-loop.md`](core/protocols/pr-review-loop.md)). |
| **18 observability skills** install via `gcx skills install --all` — no vendoring. |

---

## The operating model

```
                     ┌─────────────────────────────────────────────────┐
                     │                  AGENTS.md                       │
                     │  routing rules · safety defaults · memory keys   │
                     └────────────────────┬────────────────────────────┘
                                          │
            ┌─────────────────────────────┼─────────────────────────────┐
            │                             │                              │
   ┌────────▼────────┐         ┌─────────▼─────────┐         ┌──────────▼────────┐
   │  Specialist     │         │   Durable state   │         │   Local knowledge  │
   │  sub-agents     │         │   (bd / Beads)    │         │   base + Graphify  │
   │                 │         │                   │         │                    │
   │ task-planner    │         │ tasks, comments,  │         │ references/        │
   │ tool-researcher │         │ memories, ready   │         │   index.md         │
   │ helm-engineer   │         │ queues survive    │         │   log.md           │
   │ argocd-engineer │◄────────┤ compaction        │────────►│   learnings-*.md   │
   │ platform-engr   │         │                   │         │ (Karpathy LLM      │
   │ pr-reviewer     │         └─────────┬─────────┘         │  Wiki pattern) +   │
   │ worker          │                   │                   │ graph queries      │
   └────────┬────────┘                   │                   └────────────────────┘
            │                            ▼
            │            ┌────────────────────────────────┐
            └───────────►│   Skills (executable playbooks) │
                         │                                  │
                         │   shiny-engineer · create-pr ·   │
                         │   helm-upgrade · k8s-debug ·     │
                         │   graphify · contract-validation │
                         │                                  │
                         │   + 18 observability skills      │
                         │     via `gcx skills install`     │
                         └────────────────┬─────────────────┘
                                          │
                              ┌───────────▼────────────┐
                              │   Token economics      │
                              │                        │
                              │   rtk command policy   │
                              │   (native / rtk-safe / │
                              │    raw-required)       │
                              └────────────────────────┘
```

The compaction-and-recovery loop is documented end-to-end in [`LIFECYCLE.md`](LIFECYCLE.md).

## 5-minute adoption

```bash
# 1. Install the three required tools
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash   # bd
pipx install graphify                                                                          # graph
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | bash               # rtk

# Optional: Grafana stack? Install gcx + the 18-skill bundle.
brew install grafana/grafana/gcx
gcx skills install --all                                                                       # → ~/.agents/skills/

# 2. Clone the harness somewhere you can reference it
git clone https://github.com/<owner>/platform-agent-harness ~/platform-agent-harness
export HARNESS=~/platform-agent-harness

# 3. Drop the instruction contract into your infra repo
cp "$HARNESS/templates/AGENTS.template.md" ./AGENTS.md

# 4. Initialize task state and build a repo graph
bd init && bd prime
graphify . --no-viz

# 5. Wire your runtime — pick one from adapters/
cat "$HARNESS/adapters/<your-runtime>/README.md"
```

Customize the placeholders in `AGENTS.md` (cluster naming, repo conventions, contact names) and you are running. Every adapter README has a concrete file-mapping table, copy commands, and verification steps.

For a public companion repo using this exact operating model, see [`Thakurvaibhav/k8s`](https://github.com/Thakurvaibhav/k8s) — a GitOps-driven "Platform in a Box" with Argo CD App-of-Apps, Envoy Gateway, Prometheus/Thanos, Kyverno, and Sealed Secrets.

## What is in the box

| Layer | Path | What it provides |
| --- | --- | --- |
| Agent prompts | [`core/agents/`](core/agents/) | 7 specialist sub-agents (planner, researcher, helm, argocd, platform/observability, PR reviewer, worker) with explicit "when to invoke / when NOT to invoke" boundaries |
| Protocols | [`core/protocols/`](core/protocols/) | 8 canonical rules: harness-pillars, delegation, bd-and-memory, rtk-command-policy, graphify-first, pr-review-loop, parallel-dispatch, safety-and-handoff |
| Skills | [`skills/`](skills/) | 6 portable executable playbooks (shiny-engineer, create-pr, helm-upgrade, k8s-debug, graphify, contract-validation); observability skills live in `gcx skills install` |
| Domain packs | [`domain-packs/`](domain-packs/) | Kubernetes safety, Helm essentials, observability-via-gcx — focused, not exhaustive |
| Hooks | [`core/hooks/`](core/hooks/) | Transcript-parsing pre-compact memory snapshot, rtk autoprefix, context-threshold warning |
| Tools | [`tools/`](tools/) | One-pagers for bd, Graphify, rtk, gcx with upstream install links |
| Adapters | [`adapters/`](adapters/) | Concrete wiring for 6 CLI agent runtimes |
| References | [`references/`](references/) | Hand-curated local knowledge base for agents — `index.md`, `log.md`, numbered `learnings-*.md` (Karpathy LLM Wiki pattern, see [`references/README.md`](references/README.md)) |
| Templates | [`templates/`](templates/) | `AGENTS.template.md` to drop into your repo + dispatch / handoff / validation contracts |
| Examples | [`examples/`](examples/) | 2 end-to-end worked stories: Helm chart upgrade and alert investigation |
| Sanitization | [`sanitization/`](sanitization/) | Pre-publish gate using trufflehog + gitleaks + local denylist |

## Knowledge feedback loop

Every sub-agent ends a non-trivial task with a four-step **Task Completion Checklist** (canonical: [`core/protocols/bd-and-memory.md`](core/protocols/bd-and-memory.md)):

1. `bd remember` — persist any non-obvious finding as a self-contained memory.
2. Append one line to [`references/log.md`](references/log.md).
3. If a finding refines or contradicts an existing item, update or `CONFLICT:`-flag the right `references/learnings-*.md` entry.
4. Update [`references/index.md`](references/index.md) only when a doc was added or removed.

The handoff report has a mandatory `## Knowledge updates` section ([`templates/handoff-report.template.md`](templates/handoff-report.template.md)) — agents must list what they changed, or write `None.` next to each row. This is the explicit gate that keeps the local knowledge base alive across sessions.

## What this is not

- Not a documentation library. Every file pulls weight in a real agent session.
- Not org-specific. Real cluster names, ticket prefixes, and internal URLs have been redacted. The patterns are portable.
- Not a fork of any agent runtime. The same instruction contract loads under all six runtimes via the adapters.

## Safety defaults

- No mutating Kubernetes commands (`apply|create|delete|patch|replace|edit|scale|rollout|...`).
- No `helm install|upgrade|uninstall|rollback`.
- No pushes to `main` / `master`; no force-push to protected branches.
- Read-only by default; runtime denylists pin the rest.
- All examples and templates use synthetic placeholders (`<cluster>`, `<service>`, `<TICKET-KEY>`).

## Credits

The patterns here come from production platform-engineering work. The harness vendors and sanitizes that work into a portable kit. The agent runtimes and tools it composes are all upstream open-source projects — see [`installation/prerequisites.md`](installation/prerequisites.md).
