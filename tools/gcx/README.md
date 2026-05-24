# gcx

`gcx` is Grafana's CLI for managing and querying Grafana / Grafana Cloud resources from the terminal. It is optimized for agentic usage and is the harness's recommended source for observability workflows.

- Upstream repo: <https://github.com/grafana/gcx>
- Bundled skills repo: <https://github.com/grafana/skills>
- Documentation: <https://grafana.com/docs/grafana/latest/as-code/observability-as-code/grafana-cli/>

## Why the harness uses it

- **Cross-signal RCA.** Metrics, logs, traces, profiles, alerts, SLOs, IRM/on-call, synthetic monitoring, k6, AI Observability, Knowledge Graph, and incidents in one CLI.
- **Structured output.** `-o json` produces parser-friendly responses for agents.
- **Ships its own skill bundle.** The harness does not need to vendor observability skills; `gcx skills install` distributes a curated 18-skill bundle to `~/.agents/skills` using the `.agents` cross-tool convention.

## Install

```bash
brew install grafana/grafana/gcx
```

Or download a release binary from <https://github.com/grafana/gcx/releases>.

Verify:

```bash
gcx --version
```

## Configure

Use the bundled `setup-gcx` skill (see below) for first-time configuration, or:

```bash
gcx config set contexts.<name>.grafana.server https://<stack>.grafana.net
gcx config set contexts.<name>.grafana.token <service-account-token>
gcx config use-context <name>
gcx config check
```

Never commit tokens or stack identifiers.

## Skill bundle

`gcx` ships a portable, agent-runtime-neutral skill bundle. The harness recommends installing it instead of vendoring observability skills, so updates flow from the upstream Grafana repo.

```bash
gcx skills list                       # show the 18 bundled skills
gcx skills install --all              # install everything into ~/.agents/skills
gcx skills install setup-gcx debug-with-grafana investigate-alert
gcx skills install --all --dry-run    # preview without writing
```

Install location is `~/.agents/skills/<skill>/SKILL.md` by default; override with `--dir <path>`. Agents that follow the `.agents` convention (Claude Code, Codex CLI, OpenCode, and others) auto-discover skills there. For runtimes that load from a different directory, symlink or pass `--dir` to install into the runtime's expected location.

### Bundled skill catalog

| Skill | Use for |
| --- | --- |
| `setup-gcx` | First-time `gcx` configuration: contexts, auth, default datasources, CI/CD env vars, troubleshooting. |
| `gcx` | General-purpose `gcx` usage. |
| `gcx-observability` | End-to-end Grafana Cloud observability rollout: instrumentation, SLOs, alerting, synthetic, k6, IRM, dashboards, cost optimization, GitOps export. |
| `explore-datasources` | Discover datasources, metrics, labels, log streams. |
| `debug-with-grafana` | 7-step diagnostic workflow for HTTP 5xx / latency / outage incidents. |
| `investigate-alert` | RCA workflow for a firing/pending alert. |
| `slo-check-status` | Overview of SLO health, error budget, burn rate. |
| `slo-investigate` | Deep-dive RCA for a breaching SLO. |
| `slo-manage` | Create / update / pull / push / delete SLO definitions. |
| `slo-optimize` | Trend analysis and tuning recommendations. |
| `synth-check-status` | Health and trend overview for SM checks. |
| `synth-investigate-check` | Diagnose failing SM checks. |
| `synth-manage-checks` | Create / update / pull / push / delete SM checks. |
| `manage-dashboards` | Pull/push dashboards, validate, promote across envs, snapshot panels. |
| `import-dashboards` | Convert existing dashboards to Go builder code. |
| `generate-resource-stubs` | Generate Go stubs for new dashboards / alert rules. |
| `scaffold-project` | Bootstrap a new dashboards-as-code repo. |
| `aio11y` | AI Observability for LLM apps. |

Run `gcx skills list --output yaml` for the live, version-pinned descriptions.

## Decision tree

1. Try Grafana MCP for simple dashboard / datasource / Prometheus / Loki operations.
2. Use `gcx --agent` or the matching bundled skill when MCP is missing an endpoint, returns incomplete output, or times out.
3. Go directly to `gcx` for SLOs, Knowledge Graph, synthetic monitoring, on-call/incident data, AI Observability, or cross-signal RCA.

## Pattern

```bash
gcx --agent <resource> <command> -o json
```

Prefix with `rtk` only when the command is read-only and not piped or chained.

## Common read-only examples

```bash
gcx --agent metrics query -d <datasource-uid> '<promql>' --since 1h -o json
gcx --agent logs query -d <datasource-uid> '<logql>' --since 30m -o json
gcx --agent traces query -d <datasource-uid> '<traceql>' -o json
gcx --agent alert rules list --state firing -o json
gcx --agent slo definitions status <slo-id> -o json
gcx --agent kg health --type Service --since 1h -o json
```

## Public sharing rule

Never commit real datasource IDs, dashboard URLs, incident IDs, org names, stack URLs, or tokens.
