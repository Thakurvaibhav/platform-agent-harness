# Observability via gcx

The harness does not vendor observability skills. It points at Grafana's `gcx` bundle, which ships 18 portable skills via `gcx skills install`.

## One-time install

```bash
brew install grafana/grafana/gcx
gcx skills install --all                 # → ~/.agents/skills/
```

`~/.agents/skills/` is the cross-tool `.agents` convention. Most adapters auto-discover it. For runtimes that look elsewhere (Factory Droid uses `.factory/skills/`), pass `--dir <path>` to `gcx skills install` or symlink.

## Authenticate

```bash
gcx config set contexts.<name>.grafana.server https://<stack>.grafana.net
gcx config set contexts.<name>.grafana.token <service-account-token>
gcx config use-context <name>
gcx config check
```

Never commit tokens. See [`tools/gcx/README.md`](../../tools/gcx/README.md) for the full setup, on-prem / CI variants, and TLS options.

## Routing intents to bundled skills

| User intent | Bundled skill |
| --- | --- |
| First-time gcx setup, auth, contexts | `setup-gcx` |
| Errors / latency / outage RCA | `debug-with-grafana` |
| Diagnose a firing alert | `investigate-alert` |
| SLO health overview | `slo-check-status` |
| Breaching SLO RCA | `slo-investigate` |
| Create / change SLO | `slo-manage` |
| Tune SLO objectives or windows | `slo-optimize` |
| SM check health | `synth-check-status` |
| Failing SM check RCA | `synth-investigate-check` |
| Create / change SM check | `synth-manage-checks` |
| Dashboard CRUD, promotion, snapshots | `manage-dashboards` |
| Convert existing dashboards to code | `import-dashboards` |
| Generate new dashboard / alert stubs | `generate-resource-stubs` |
| Start a dashboards-as-code repo | `scaffold-project` |
| AI Observability for LLM apps | `aio11y` |
| End-to-end Grafana Cloud setup | `gcx-observability` |
| Explore what data exists | `explore-datasources` |
| Generic Grafana resource CRUD | `gcx` |

Run `gcx skills list --output yaml` for the live, version-pinned descriptions.

## Decision tree

1. Try Grafana MCP for simple dashboard / datasource / Prometheus / Loki operations.
2. Fall back to `gcx --agent` (or the matching bundled skill) when MCP is missing an endpoint, returns incomplete output, or times out.
3. Go directly to `gcx` for SLOs, Knowledge Graph, synthetic monitoring, on-call/incident data, AI Observability, or cross-signal RCA.

## Query pattern (manual)

When the bundled skill doesn't fit:

```bash
gcx --agent metrics query -d <datasource-uid> '<promql>' --since 1h -o json
gcx --agent logs query -d <datasource-uid> '<logql>' --since 30m -o json
gcx --agent traces query -d <datasource-uid> '<traceql>' -o json
gcx --agent alert rules list --state firing -o json
gcx --agent slo definitions status <slo-id> -o json
gcx --agent kg health --type Service --since 1h -o json
```

Prefix with `rtk` for read-only queries.

## RCA pattern

1. Start with the alert or symptom.
2. Identify the affected entity and time window.
3. Query metrics for saturation, errors, latency, and traffic.
4. Query logs for new error patterns.
5. Query traces / profiles if latency or resource issues are unclear.
6. Check related incidents or on-call context only when relevant.
7. Capture the confirmed root cause as a durable memory:

```bash
bd remember "<symptom>: root cause <X>; fix <Y>" --key <repo>/trouble/<topic>
```

## Public sharing rule

Never commit real datasource UIDs, org names, dashboard URLs, incident IDs, on-call schedules, or stack URLs.
