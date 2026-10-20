# Playbook: Alert Investigation (Read-Only SRE Triage)

Harness-neutral procedure for the [`alert-investigator`](../../core/agents/alert-investigator.md)
agent. Gather evidence, compare hypotheses, and return a triage card plus any proposed
learning. Never apply, delete, scale, patch, or restart resources.

See also: [`learnings-observability.md`](learnings-observability.md), [`learnings-istio.md`](learnings-istio.md), [`agent-knowledge/orgs/README.md`](../orgs/README.md), [`index.md`](index.md).

**Input:** a Slack link/message about an alert, or an alert title/name. **Output:** triage card.

## Tool posture

Use any available read-only tool that fits. Discover the connected tool names and
capabilities before using them; integrations vary by runtime and installation.

- **Grafana MCP**: alert groups/rules, Prometheus queries, Loki logs, Sift analyses,
  annotations, dashboards, panel queries, oncall.
- **Your incident-management tool, if you have one**: incidents, alerts, oncall
  schedules, responder availability. Its absence does not prevent triage.
- **gcx CLI**: alert rules, metrics, SLO burn, logs, oncall, incidents where configured.
- **Slack read access**: read the alert thread/message. If unavailable, use pasted text
  or the alert title and report the missing thread context.
- **kubectl (read-only)**: get, describe, events, logs, top.
- **gcloud / aws (read-only)**: describe, list, get, log queries for infrastructure alerts.
- **Container image inspection**: `crane` or `docker save`, then read the bundle (Step 4c).
- **Skill procedures**: read [`skills/k8s-debug/SKILL.md`](../../skills/k8s-debug/SKILL.md)
  and apply only read-only steps with available tools.

## Steps

**0. Load context first.** Run `bd prime --memories-only` and
`agent-knowledge/scripts/knowledge-search.sh '<alert keywords>'`. Read the operator's
cluster registry using the instance-tier guidance in
[`agent-knowledge/orgs/README.md`](../orgs/README.md). Real registries are supplied by
the operator; they do not ship in this public repo. If missing, request the relevant
cluster context and mark estate facts unverified until supplied.

**0.5. Preflight capabilities.** Check only the tools needed for the target. For example:

```bash
kubectl --context='<context>' auth can-i --list >/dev/null 2>&1 && echo "kubectl OK" || echo "kubectl BLOCKED"
gcloud auth print-access-token >/dev/null 2>&1 && echo "gcloud OK" || echo "gcloud BLOCKED"
```

These checks do not prove every resource is readable; record individual permission
failures as they occur. Put blocked capabilities on a **`BLOCKED:`** line at the top
of the triage card with a verified unblock command or the specific access needed.
Recommend authentication changes to the human; do not execute them. Continue with
working tools and state which conclusions depend on missing access.

**1. Resolve the alert.**

- Slack input: read the thread and extract alert name, cluster/namespace/service labels,
  severity, firing-since, runbook link, and human notes.
- Title input: find the rule, current state, and labels in Grafana or gcx.
- If multiple matches remain, ask which alert the user means.

**2. Map to estate.** Use labels and the operator's cluster registry to identify
environment, provider, cluster, owning team, and kube-context. Look up current oncall
in Grafana or your incident-management tool, if you have one; report it as unknown
when unavailable.

**3. Check known patterns.** Search [`learnings-observability.md`](learnings-observability.md),
[`learnings-istio.md`](learnings-istio.md), and prior memories. If current evidence
matches a documented benign pattern, return the card with its citation and stop.
A similar alert name alone is not enough to classify the incident as benign.

**4. Gather signals (parallel where possible, all read-only).**

- **Alert query**: re-run the rule's PromQL over the firing window; distinguish an ongoing
  breach from a resolved flap.
- **Metrics**: related series, latency percentiles, error ratios, cluster/namespace breakdowns.
- **Logs**: query Loki for the affected workload and window; quote decisive error lines.
- **Cluster**: read pods, workload descriptions, restart counts, probes, and OOM evidence.
  Event retention varies by cluster. If events have expired, use restart counts and
  Loki pod-name continuity, and state the evidence limitation.
- **Cloud**: for node pressure, load balancer, quota, or NAT symptoms, use read-only
  gcloud/aws queries and cloud logs.
- **Sift / dashboards**: inspect available analyses and the owning dashboard's panel queries.

**4a. Resolve the call path before blaming a hop.** When service A cannot reach service B,
a public HTTPRoute/Gateway or DNS record establishes a possible route, not the route
the client actually uses. Establish the path from:

- **The image**: inspect the exact deployed image's base-URL configuration, for example
  `SERVICE_URL: {default: "http://<service>"}`. Check how environment variables and
  mounted configuration override defaults; URL-looking names may serve other purposes.
- **The wire**: proxy or ztunnel access logs identifying destination service, port,
  and workload identities where available.

Only then assess a gateway, CDN, NAT, or ingress hypothesis.

**4b. Ambient-mesh clusters: inspect L4 signals.** Check whether the affected workloads
use ambient mode and whether a waypoint provides L7 telemetry. Missing
`istio_requests_total` does not establish that traffic stopped. Discover the available
connection metrics and labels before querying opened, closed, and failed connections;
candidate names include `istio_tcp_connections_{opened,closed,failed}_total`.

Compare counter increases over the incident window, not raw cumulative values.
Zero increases can support a client-side stall hypothesis only after verifying metric
coverage, selectors, and scrape continuity. They do not prove a connection-pool deadlock
or rule out a network fault; corroborate with client evidence and account for existing
connections. Check the deployed proxy's access-log emission behavior before treating
missing log lines as missing traffic.

**4c. Inspect container configuration without exec.** Do not use `kubectl exec`.
Inspect the exact deployed image, preferably by digest, using `crane`; unpack it and
read the configuration/bundle. This establishes build-time defaults, not live process
state. Compare the pod's environment and configuration references without exposing
secrets, and state what remains unverified. Remove only scratch exports you created.

**5. Correlate.** Compare recent deployments, ArgoCD sync history where applicable,
merged PRs, co-firing alerts, annotations, and open incidents in your incident-management
tool, if you have one. Consider changes, dependencies, and infrastructure.

**6. Give a verdict.** Rank hypotheses; quantify scope and user/SLO impact; state
confidence (high/medium/low and why); provide **one actionable next step** with an owner.
Recommend remediation, never execute it.

**6.5. Grade detection.** Compare the alert's firing time with the incident onset in
metrics. If detection was late, quantify the delay and inspect the rule's `for:`,
volume floor, and behavior during a total outage. Test whether an error-ratio rule's
volume gate suppressed a low-volume outage. Put the result in `DETECTION:`; if onset
is unknown, state that limitation.

## Output: triage card

```text
BLOCKED: <tool + verified unblock command or required access; omit if none>
ALERT: <name> · <severity> · <cluster>/<env> · <service> (owner: <team>)
       Fired <timestamp> · <FIRING NOW | RESOLVED at timestamp>
STATUS: <incident window from metrics; self-healed / fixed / ongoing / unverified>
SCOPE: <pods/nodes/clusters/requests affected, and for how long>
LIKELY CAUSE: <ranked hypothesis> (confidence: <H/M/L> + why)
EVIDENCE: <2–4 decisive signals with actual queries/commands and outputs>
IMPACT: <quantified user-facing / SLO / internal impact, or unknown>
DETECTION: <on-time / delay and cause / unverified>
KNOWN PATTERN: <learning citation if matched, otherwise novel>
NEXT STEP: <one concrete recommendation and owner/oncall>
ASSUMPTIONS: <unverified facts, missing evidence, and competing explanations>
```

**7. Propose capture.** If a novel reusable gotcha surfaced, propose a `bd remember`
or [`learnings-observability.md`](learnings-observability.md) entry. Do not write
memories or approve production learnings during a read-only investigation.

**8. Optional Slack reply.** Return the triage card as a text draft. Never send it.
End the draft with 🤖 on its own last line.

## Hard rules

- Read-only. Put required mutations in `NEXT STEP` for a human. Do not acknowledge,
  resolve, or silence alerts/incidents, edit repositories, or send messages.
- **An empty result is evidence only after the stream is proven live.** Relax filters
  to show the metric/log stream exists and has data in the same window. A nonexistent
  metric, unshipped log stream, or wrong label selector is not a clean bill of health.
  State the control beside every empty result.
- Every causal claim carries its actual query/command and output, a log line, or a
  manifest location. Give reasons for ranked alternatives.
- Cite estate facts from the operator's registry or observed evidence, never infer
  them from names. Keep assumptions separate from verified findings.
- Keep the card concise.
