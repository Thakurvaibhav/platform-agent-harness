# Reference Index

Master catalog for the harness. Agents check this file **before** broad searches when they need to know whether guidance already exists.

> **Maintenance:** Update this file whenever you add or remove a doc. Update only the affected row.

## Root

| Path | Purpose |
| --- | --- |
| [`README.md`](../README.md) | Project positioning, value-prop numbers, 5-minute adoption, repository map |
| [`AGENTS.md`](../AGENTS.md) | Instructions for agents working inside the harness source repo itself |
| [`LIFECYCLE.md`](../LIFECYCLE.md) | Canonical bd memory + compaction lifecycle, with diagram |
| [`templates/AGENTS.template.md`](../templates/AGENTS.template.md) | Instruction contract that users copy into their infra repo |
| [`references/README.md`](README.md) | How the local knowledge base works + Karpathy LLM Wiki credit |
| [`references/index.md`](index.md) | This master catalog |
| [`references/log.md`](log.md) | Append-only work-log chronology |

## Core protocols

| Path | Purpose |
| --- | --- |
| [`core/protocols/harness-pillars.md`](../core/protocols/harness-pillars.md) | The seven pillars: specialist agents, bd substrate, indexed knowledge, Graphify, skills, safety, token economics |
| [`core/protocols/delegation.md`](../core/protocols/delegation.md) | Routing table, when NOT to delegate, dispatch prompt shape |
| [`core/protocols/bd-and-memory.md`](../core/protocols/bd-and-memory.md) | Single source of truth for bd, memory keys, code quality, worktrees, post-deploy validation, completion checklist |
| [`core/protocols/rtk-command-policy.md`](../core/protocols/rtk-command-policy.md) | `native-tool` / `rtk-safe` / `raw-required` classification + allow/deny lists |
| [`core/protocols/graphify-first.md`](../core/protocols/graphify-first.md) | When and how to query the repo knowledge graph |
| [`core/protocols/pr-review-loop.md`](../core/protocols/pr-review-loop.md) | Dispatch matrix + known-bot reply protocol + iteration cap |
| [`core/protocols/parallel-dispatch.md`](../core/protocols/parallel-dispatch.md) | Fan-out pattern for same-playbook work across N targets |
| [`core/protocols/safety-and-handoff.md`](../core/protocols/safety-and-handoff.md) | Git / k8s / file / secret safety + the canonical handoff contract |

## Agents

| Path | Purpose |
| --- | --- |
| [`core/agents/task-planner.md`](../core/agents/task-planner.md) | Project planning and task decomposition |
| [`core/agents/tool-researcher.md`](../core/agents/tool-researcher.md) | Production-readiness research |
| [`core/agents/helm-engineer.md`](../core/agents/helm-engineer.md) | Helm charts and values |
| [`core/agents/argocd-engineer.md`](../core/agents/argocd-engineer.md) | ArgoCD and GitOps enablement |
| [`core/agents/platform-engineer.md`](../core/agents/platform-engineer.md) | CI, alerting, observability |
| [`core/agents/pr-reviewer.md`](../core/agents/pr-reviewer.md) | PR review and CI feedback |
| [`core/agents/general-engineer.md`](../core/agents/general-engineer.md) | General-purpose engineering, research, validation |


## Skills

| Path | Purpose |
| --- | --- |
| [`skills/shiny-engineer/SKILL.md`](../skills/shiny-engineer/SKILL.md) | Structured implementation workflow (Design → Implement → Review → Test → Submit, rule-of-five expansion) |
| [`skills/create-pr/SKILL.md`](../skills/create-pr/SKILL.md) | PR creation workflow |
| [`skills/helm-upgrade/SKILL.md`](../skills/helm-upgrade/SKILL.md) | Helm dependency upgrade workflow |
| [`skills/k8s-debug/SKILL.md`](../skills/k8s-debug/SKILL.md) | Read-only Kubernetes debugging |
| [`skills/graphify/SKILL.md`](../skills/graphify/SKILL.md) | Graphify build/query workflow |
| [`skills/contract-validation/SKILL.md`](../skills/contract-validation/SKILL.md) | Contract-driven validation workflow |
| (external) | The 18-skill Grafana bundle installed via `gcx skills install --all` → `~/.agents/skills/` |

## Domain packs

| Path | Purpose |
| --- | --- |
| [`domain-packs/kubernetes-safety/README.md`](../domain-packs/kubernetes-safety/README.md) | Read-only defaults, multi-context awareness, post-deploy validation patterns |
| [`domain-packs/helm-essentials/README.md`](../domain-packs/helm-essentials/README.md) | Wrapper-chart pattern, hardening rules, YAML formatting gotchas, CI registration |
| [`domain-packs/observability-via-gcx/README.md`](../domain-packs/observability-via-gcx/README.md) | gcx skill bundle routing, decision tree, RCA pattern |

## Topic learnings

| Path | Domain | Keywords | Cross-refs |
| --- | --- | --- | --- |
| [`references/learnings-helm-ci.md`](learnings-helm-ci.md) | YAML formatting, Helm patterns, dependency handling, GitHub Actions, workflow pinning | helm, chart, values, yaml, yamlfmt, CI, GitHub Actions, workflow, dependency, lint | `learnings-argocd.md` |
| [`references/learnings-argocd.md`](learnings-argocd.md) | ArgoCD sync behavior, ignoreDifferences, sync-waves, values key naming | argocd, sync, ignoreDifferences, sync-wave, values key, CRD, Application | `learnings-helm-ci.md`, `learnings-progressive-delivery.md` |
| [`references/learnings-observability.md`](learnings-observability.md) | PromQL, alerting, ServiceMonitor, Grafana dashboards | prometheus, promql, alerting, grafana, dashboard, ServiceMonitor, metrics | — |
| [`references/learnings-rollout.md`](learnings-rollout.md) | Rollout strategy, staged migrations, batch campaign hygiene | rollout, migration, batch, campaign, phased, staged, gap-fill, validation | — |
| [`references/learnings-progressive-delivery.md`](learnings-progressive-delivery.md) | Argo Rollouts + Gateway API plugin patterns, ArgoCD ignoreDifferences for Rollout-managed resources | argo rollouts, canary, progressive, Gateway API, httpRoute, header routing, workloadRef | `learnings-argocd.md`, `learnings-helm-ci.md` |
| [`references/learnings-operators.md`](learnings-operators.md) | Operators, CRDs, policy-engine patterns (guard/mutation/audit), admission-controller cache gotchas | kyverno, tetragon, CRD, operator, policy, mutating, validating, reconciliation | `learnings-argocd.md` |
| [`references/learnings-k8s-sa.md`](learnings-k8s-sa.md) | ServiceAccount separation, Workload Identity (GKE WI / EKS IRSA), image-pull secrets, batch SA rollout | ServiceAccount, SA, Workload Identity, imagePullSecrets, GKE, EKS, IAM | — |
| [`references/learnings-agent-workflow.md`](learnings-agent-workflow.md) | Sub-agent dispatch pitfalls, parallel work, knowledge capture | dispatch, subagent, timeout, prompt, delegation, parallel | — |
| [`references/learnings-code-review.md`](learnings-code-review.md) | PR review patterns, bot interactions, CI feedback handling | review, PR, CodeRabbit, Cursor Bugbot, CI feedback, bot, false positive | — |

## Documentation folder convention

When creating domain documentation outside this repo, use these standard subfolder names:

| Folder | Contents |
| --- | --- |
| playbooks | Step-by-step operational procedures |
| research | Investigation reports, feasibility studies |
| reports | Point-in-time audit/validation outputs (dated) |
| tests | Test plans and test result reports |
| tools | Scripts and utilities |
| design | Architecture proposals, experiment specs |
| summaries | Frozen project writeups (historical) |

## Tools

| Path | Purpose |
| --- | --- |
| [`tools/README.md`](../tools/README.md) | External tool overview + install order |
| [`tools/bd/README.md`](../tools/bd/README.md) | bd install and workflow (<https://github.com/steveyegge/beads>) |
| [`tools/graphify/README.md`](../tools/graphify/README.md) | Graphify install and graph-first usage (<https://github.com/safishamsi/graphify>) |
| [`tools/rtk/README.md`](../tools/rtk/README.md) | rtk install and command policy (<https://github.com/rtk-ai/rtk>) |
| [`tools/gcx/README.md`](../tools/gcx/README.md) | Grafana CLI + `gcx skills install` bundle (<https://github.com/grafana/gcx>) |

## Hooks and runtime UX

| Path | Purpose |
| --- | --- |
| [`core/hooks/README.md`](../core/hooks/README.md) | Hook catalog and design rules |
| [`core/hooks/generic/pre-task-check.sh`](../core/hooks/generic/pre-task-check.sh) | Portable session-start hook |
| [`core/hooks/generic/post-task-memory.sh`](../core/hooks/generic/post-task-memory.sh) | Portable `bd remember` helper with sanitization guard |
| [`core/hooks/generic/rtk-wrapper.sh`](../core/hooks/generic/rtk-wrapper.sh) | Portable rtk command wrapper |
| [`core/hooks/generic/knowledge-search.sh`](../core/hooks/generic/knowledge-search.sh) | Search bd memories + learnings + domain docs with OR-matching across query terms |
| [`core/hooks/generic/drift-check.sh`](../core/hooks/generic/drift-check.sh) | Harness health: graph freshness, learnings staleness, memory bloat, consolidation overdue |
| [`core/hooks/factory-droid/rtk-autoprefix.py`](../core/hooks/factory-droid/rtk-autoprefix.py) | PreToolUse hook preserving `sudo`/`env=`/`time` prefixes |
| [`core/hooks/factory-droid/pre-compact-bd-sync.py`](../core/hooks/factory-droid/pre-compact-bd-sync.py) | PreCompact transcript parser → bd memory + per-task comments |
| [`core/hooks/factory-droid/post-compact-prime-reminder.sh`](../core/hooks/factory-droid/post-compact-prime-reminder.sh) | SessionStart `bd prime` |
| [`core/hooks/factory-droid/ctx-threshold-warn.py`](../core/hooks/factory-droid/ctx-threshold-warn.py) | UserPromptSubmit hook nudging `/compact` past threshold |
| [`core/statusline/statusline.sh`](../core/statusline/statusline.sh) | Minimal statusline with repo / branch / Graphify / bd indicators |
| [`core/statusline/statusline-context.py`](../core/statusline/statusline-context.py) | Generic JSONL transcript parser used by statusline + threshold hook |

## Installation and adapters

| Path | Purpose |
| --- | --- |
| [`installation/prerequisites.md`](../installation/prerequisites.md) | Required + optional tools with upstream links |
| [`installation/hook-installation.md`](../installation/hook-installation.md) | Recommended hook points table |
| [`installation/command-denylist.md`](../installation/command-denylist.md) | Runtime command denylist seed |
| [`adapters/README.md`](../adapters/README.md) | Shared adoption flow + where-each-runtime-looks matrix |
| [`adapters/aider/README.md`](../adapters/aider/README.md) | Aider adapter |
| [`adapters/claude-code/README.md`](../adapters/claude-code/README.md) | Claude Code adapter |
| [`adapters/codex-cli/README.md`](../adapters/codex-cli/README.md) | Codex CLI adapter |
| [`adapters/factory-droid/README.md`](../adapters/factory-droid/README.md) | Factory Droid adapter |
| [`adapters/goose/README.md`](../adapters/goose/README.md) | Goose adapter |
| [`adapters/opencode/README.md`](../adapters/opencode/README.md) | OpenCode adapter |

## Templates and examples

| Path | Purpose |
| --- | --- |
| [`templates/README.md`](../templates/README.md) | Template catalog |
| [`templates/AGENTS.template.md`](../templates/AGENTS.template.md) | Drop-in `AGENTS.md` for your infra repo |
| [`templates/dispatch-prompt.template.md`](../templates/dispatch-prompt.template.md) | Canonical dispatch prompt shape |
| [`templates/handoff-report.template.md`](../templates/handoff-report.template.md) | Sub-agent handoff contract |
| [`templates/validation-contract.template.md`](../templates/validation-contract.template.md) | Pass/fail assertion contract |
| [`templates/validation-report.template.json`](../templates/validation-report.template.json) | Machine-readable validation report |
| [`templates/redaction-denylist.template.txt`](../templates/redaction-denylist.template.txt) | Local denylist seed |
| [`templates/commands/consolidate.md`](../templates/commands/consolidate.md) | Knowledge consolidation command template |
| [`examples/README.md`](../examples/README.md) | Worked example catalog |
| [`examples/helm-chart-upgrade.md`](../examples/helm-chart-upgrade.md) | End-to-end Helm chart upgrade flow exercising 6 sub-agents |
| [`examples/alert-investigation.md`](../examples/alert-investigation.md) | Alert RCA via the gcx bundled skills |

## Sanitization

| Path | Purpose |
| --- | --- |
| [`sanitization/prepublish-checklist.md`](../sanitization/prepublish-checklist.md) | Pre-publish gate: trufflehog + gitleaks + local denylist + format check |
