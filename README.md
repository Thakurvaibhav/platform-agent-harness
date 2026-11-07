# Platform Agent Harness

[![gates](https://github.com/Thakurvaibhav/platform-agent-harness/actions/workflows/ci.yml/badge.svg)](https://github.com/Thakurvaibhav/platform-agent-harness/actions/workflows/ci.yml) [![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

**Turn a CLI coding agent into a coordinated platform engineering teammate.**

A runtime-neutral behavioural spec and coordination protocol for agents doing Kubernetes, Helm,
ArgoCD, CI and observability work. Most agent setups stop at "give it a system prompt". This is
everything around the prompt: dispatch, memory that survives compaction, a second opinion on risky
PRs, and safe-by-default command policy.

Runs under [Claude Code](https://code.claude.com/), [Codex CLI](https://developers.openai.com/codex/cli),
[Factory Droid](https://factory.ai/), [OpenCode](https://opencode.ai/), [Goose](https://block.github.io/goose/)
and [Aider](https://aider.chat/).

**[Read the illustrated overview](https://thakurvaibhav.github.io/platform-agent-harness/)**, which
has the diagrams this README deliberately does not.

## Install

```bash
# 1. The three tools the harness composes
curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash   # bd
pipx install graphify                                                                          # graph
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | bash               # rtk

# 2. Clone it somewhere you can reference
git clone https://github.com/Thakurvaibhav/platform-agent-harness ~/platform-agent-harness
export HARNESS=~/platform-agent-harness

# 3. Drop the instruction contract into your infra repo
cp "$HARNESS/templates/AGENTS.template.md" ./AGENTS.md

# 4. Initialise task state and build a repo graph
bd init && bd prime
graphify . --no-viz

# 5. Wire your runtime
cat "$HARNESS/adapters/<your-runtime>/README.md"
```

Fill in the placeholders in `AGENTS.md` (cluster naming, repo conventions, contacts) and you are
running. Each adapter README carries a file-mapping table, copy commands and verification steps.

Running Grafana? `brew install grafana/grafana/gcx && gcx skills install --all` adds 18
observability skills to `~/.agents/skills/`. Nothing is vendored here.

## What you get

| | Count | Where |
| --- | --- | --- |
| Specialist sub-agents | 8 | [`core/agents/`](core/agents/) |
| Canonical protocols | 11 | [`core/protocols/`](core/protocols/) |
| Executable skills | 16 | [`skills/`](skills/) |
| Runtime adapters | 6 | [`adapters/`](adapters/) |
| Domain packs | 3 | [`domain-packs/`](domain-packs/) |
| Hooks | 10 | [`core/hooks/`](core/hooks/) |
| Worked examples | 2 | [`examples/`](examples/) |
| Curated learnings | 25 files, 1,766 entries | [`agent-knowledge/references/`](agent-knowledge/references/) |

Plus [`templates/`](templates/) for the instruction contract and the dispatch, handoff and
validation shapes; [`tools/`](tools/) one-pagers; and [`sanitization/`](sanitization/), a
pre-publish gate over trufflehog, gitleaks and a local denylist.

## How it fits together

`AGENTS.md` is the contract every agent reads at birth: routing rules, safety defaults, memory
keys. From there three things carry state between sessions.

**Specialist sub-agents** take scoped work, one job each, with explicit "when NOT to invoke"
boundaries. **[`bd`](https://github.com/steveyegge/beads)** holds tasks, comments and durable
memories, so a compaction costs nothing. **[`agent-knowledge/`](agent-knowledge/)** is a
hand-curated markdown knowledge base that agents read *before* they grep the repo, in the shape of
[Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

That knowledge splits in two, which is what makes the harness survive a job change: a **portable
tier** (`references/`, method and tool behaviour) and an **instance tier**
([`agent-knowledge/orgs/<org>/`](agent-knowledge/orgs/), cluster registries and anything true of one estate). One switch in
[`agent-knowledge/env.sh`](agent-knowledge/env.sh) moves every machine path and the active org. See
[`core/protocols/knowledge-tiers.md`](core/protocols/knowledge-tiers.md) and the runbook at
[`installation/new-org-setup.md`](installation/new-org-setup.md).

Agents are required to feed it back. Every non-trivial task ends on a completion checklist that
persists findings and flags contradictions, and the [handoff report](templates/handoff-report.template.md) has a mandatory
`## Knowledge updates` section that must say what changed or say `None.`
Canonical: [`core/protocols/bd-and-memory.md`](core/protocols/bd-and-memory.md).

The compaction and recovery loop is documented end to end in [`LIFECYCLE.md`](LIFECYCLE.md).

## Why it pays off

- **~70x fewer tokens** for architecture questions, via [Graphify](https://github.com/safishamsi/graphify)
  graph queries instead of linear file reads.
- **60 to 90% compression** on verbose CLI output, via [`rtk`](https://github.com/rtk-ai/rtk), with
  no workflow change.
- **3x+ wall-clock** on N-cluster validation, via parallel dispatch
  ([`core/protocols/parallel-dispatch.md`](core/protocols/parallel-dispatch.md)).
- **A second model reviews every risky PR**, and never sees the first one's findings
  ([`core/protocols/pr-review-loop.md`](core/protocols/pr-review-loop.md)).
- **Design before code**: requirements lock, constraint inventory, candidate shapes, a multi-model
  judge panel ([`core/protocols/design-framework.md`](core/protocols/design-framework.md)).

**[Where these numbers come from](docs/evidence.md)**, quoted from the harness's own corpus with
citations you can open, including the ones that say a claim is unmeasurable at the sample size it
was taken from.

## What this is not

- Not a documentation library. Every file is loaded by an agent in a real session, or it goes.
- Not org-specific. Cluster names, ticket prefixes and internal URLs are redacted; the patterns are not.
- Not a fork of any runtime. One instruction contract loads under all six, through the adapters.

## Safety defaults

- No mutating Kubernetes verbs (`apply`, `create`, `delete`, `patch`, `replace`, `edit`, `scale`, `rollout`).
- No `helm install`, `upgrade`, `uninstall` or `rollback`.
- No pushes to the default or protected branch, resolved per repo with
  `git symbolic-ref refs/remotes/origin/HEAD` and never assumed to be `main`. No force-push to a
  protected branch.
- Read-only by default. Runtime denylists pin the rest ([`installation/command-denylist.md`](installation/command-denylist.md)).
- Examples and templates use synthetic placeholders only: `<cluster>`, `<service>`, `<TICKET-KEY>`.

## Licence and credits

[Apache-2.0](LICENSE). The knowledge corpus ships under the same licence as the code. It is
sanitized production experience, not vendor documentation, and comes without warranty like
everything else here.

The patterns come from production platform-engineering work; this repo vendors and sanitizes that
work into a portable kit. The runtimes and tools it composes are upstream open-source projects, listed
in [`installation/prerequisites.md`](installation/prerequisites.md).

For the same operating model applied in public, see
[`Thakurvaibhav/k8s`](https://github.com/Thakurvaibhav/k8s): a GitOps "Platform in a Box" with Argo
CD App-of-Apps, Envoy Gateway, Prometheus/Thanos, Kyverno and Sealed Secrets.
