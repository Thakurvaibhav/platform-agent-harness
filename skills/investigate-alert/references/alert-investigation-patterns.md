# Alert Investigation Patterns

Read-only gcx query examples for alert triage. Replace bracketed placeholders and
verify metric names, labels, command flags, and response fields against your installation.
These examples illustrate query shapes; they do not establish a diagnosis.

See also: [`agent-knowledge/references/playbook-alert-investigation.md`](../../../agent-knowledge/references/playbook-alert-investigation.md), [`tools/gcx/README.md`](../../../tools/gcx/README.md).

---

## Alert JSON Structure

Inspect `gcx alert rules list -o json` before selecting fields. This illustrative
response has alert groups containing rules; adapt the selectors if your version
returns a different envelope:

```json
[
  {
    "name": "<alert-group>",
    "file": "grafana",
    "rules": [
      {
        "state": "firing",
        "name": "<alert-name>",
        "query": "sum(rate(http_requests_total{status=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m])) > 0.05",
        "duration": 300,
        "labels": {
          "severity": "critical",
          "cluster": "<cluster>"
        },
        "annotations": {
          "summary": "High error rate detected on {{ $labels.job }}",
          "description": "Error rate is {{ $value | humanizePercentage }}",
          "runbook_url": "<runbook-url>",
          "dashboard_url": "<dashboard-url>"
        },
        "alerts": [
          {
            "labels": {
              "alertname": "<alert-name>",
              "job": "<service>",
              "namespace": "<namespace>"
            },
            "annotations": {},
            "state": "firing",
            "activeAt": "2024-01-15T10:23:45Z",
            "value": "0.08"
          }
        ],
        "type": "alerting",
        "datasourceUID": "<datasource-uid>"
      }
    ]
  }
]
```

### Key Fields

| Field | Description |
| --- | --- |
| `state` | `firing`, `pending`, `inactive` |
| `type` | `alerting` (fires alerts) or `recording` (pre-calculates metrics) |
| `query` | The PromQL or LogQL expression that drives the alert |
| `datasourceUID` | UID of the datasource to query for investigation |
| `labels` | Rule-level labels (severity, team, cluster) |
| `annotations.runbook_url` | Link to runbook; fetch with `gh api` for GitHub URLs |
| `annotations.dashboard_url` | Link to related Grafana dashboard |
| `alerts[]` | Currently firing alert instances with their label sets and current values |
| `alerts[].activeAt` | Activation timestamp; distinguish pending onset from firing time |
| `alerts[].value` | The numeric value that triggered the alert |

### Extracting the Alert Query

```bash
# Get the query for a specific alert
gcx alert rules list -o json | \
  jq -r '.[] | .rules[] | select(.name == "<AlertName>") | .query'

# Get the datasource UID for a specific alert
gcx alert rules list -o json | \
  jq -r '.[] | .rules[] | select(.name == "<AlertName>") | .datasourceUID'

# Get all currently firing instances with their label sets
gcx alert rules list -o json | \
  jq '.[] | .rules[] | select(.name == "<AlertName>") | .alerts[] | select(.state == "firing")'
```

---

## JSON Response Envelopes

Example envelopes for `-o json`; inspect the actual response before using jq:

| Command | Envelope | jq Access Pattern |
| --- | --- | --- |
| `alert rules list` | `[{name, rules: [...]}]` | `.[] \| .rules[]` |
| `datasources list` | `{"datasources": [...]}` | `.datasources[]` |
| `query` (Prometheus) | `{"status", "data": {"resultType", "result": [...]}}` | `.data.result[]` |

---

## Common Investigation Query Patterns

### Latency Alerts

For P99/P95 latency alerts:

```bash
# Current latency percentiles
gcx metrics query -d '<datasource-uid>' \
  'histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))' \
  --from now-1h --to now --step 1m -o graph

# Latency by endpoint
gcx metrics query -d '<datasource-uid>' \
  'histogram_quantile(0.99, sum by(le, job, handler) (rate(http_request_duration_seconds_bucket[5m])))' \
  --from now-1h --to now --step 1m -o json
```

### Error Rate Alerts

For alerts on HTTP 5xx or error rates:

```bash
# Overall error rate
gcx metrics query -d '<datasource-uid>' \
  'sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))' \
  --from now-1h --to now --step 1m -o graph

# Error rate by service
gcx metrics query -d '<datasource-uid>' \
  'sum by(job) (rate(http_requests_total{status=~"5.."}[5m])) / sum by(job) (rate(http_requests_total[5m]))' \
  --from now-1h --to now --step 1m -o json
```

### Resource Exhaustion Alerts

For CPU, memory, or disk alerts:

```bash
# CPU usage by pod
gcx metrics query -d '<datasource-uid>' \
  'sum by(pod) (rate(container_cpu_usage_seconds_total[5m]))' \
  --from now-1h --to now --step 1m -o graph

# Memory usage
gcx metrics query -d '<datasource-uid>' \
  'container_memory_working_set_bytes{container!=""}' \
  --from now-30m --to now --step 1m -o json

# Disk free percentage
gcx metrics query -d '<datasource-uid>' \
  'node_filesystem_avail_bytes / node_filesystem_size_bytes' \
  --from now-6h --to now --step 5m -o graph
```

### Certificate / TLS Alerts

For cert expiry alerts:

```bash
# Days until certificate expiry
gcx metrics query -d '<datasource-uid>' \
  '(certmanager_certificate_expiration_timestamp_seconds - time()) / 86400' \
  --from now-1h --to now --step 10m -o json
```

### Availability / SLO Alerts

For availability or SLO breach alerts:

```bash
# Uptime over last hour
gcx metrics query -d '<datasource-uid>' \
  'avg_over_time(up[1h])' \
  --from now-6h --to now --step 5m -o graph

# Current up/down status
gcx metrics query -d '<datasource-uid>' \
  'up == 0' \
  --from now-15m --to now --step 1m -o json
```

---

## Loki Log Investigation Patterns

After identifying an issue from metrics, correlate with logs:

```bash
# Find error logs for a service
gcx logs query -d '<loki-uid>' '{job="<service>"} |= "error"' \
  --from now-1h --to now -o json

# Find logs around the time the alert started firing (replace timestamp)
gcx logs query -d '<loki-uid>' '{namespace="<namespace>"} |= "error"' \
  --from 2024-01-15T10:00:00Z --to 2024-01-15T10:30:00Z -o json

# Rate of error log lines (for trend analysis)
gcx logs query -d '<loki-uid>' 'sum(rate({job="<service>"} |= "error" [5m]))' \
  --from now-2h --to now --step 1m -o json
```

### Querying at Scale

Loki metric queries (`rate()`, `count_over_time()`, etc.) produce one series per unique label combination. At scale this can hit the configured series limit. Aggregate to the dimensions you need:

```bash
# BAD — one series per pod/namespace/level/... combination
gcx logs query -d '<loki-uid>' 'count_over_time({job="<service>"} [5m])'

# GOOD — aggregate down to what you need
gcx logs query -d '<loki-uid>' 'sum(count_over_time({job="<service>"} [5m]))'
gcx logs query -d '<loki-uid>' 'sum by(level) (count_over_time({job="<service>"} | json [5m]))'
gcx logs query -d '<loki-uid>' 'topk(10, sum by(pod) (rate({job="<service>"} [5m])))'
```

Rule of thumb: if your query uses `rate()`, `count_over_time()`, or `bytes_over_time()`, wrap it with `sum()`, `sum by(label)`, or `topk()`.

### Stream Labels vs Extracted Labels

Loki has two kinds of labels — confusing them causes silent failures:

| Property | Stream labels | Extracted labels |
| --- | --- | --- |
| Set by | Log ingestion config | Parser stages (`\| json`, `\| logfmt`) |
| Used in | Stream selector `{job="<service>"}` | Filter expressions after `\|` |
| Indexed | Yes (fast) | No (line-by-line scan) |
| Available | Always | Only after parser stage |

Common mistakes:

- Filtering extracted labels in `{}` — fails silently: `{namespace="<namespace>", pod="<pod>"}` won't work if `pod` is extracted, not a stream label
- Using `label_format` to rename extracted fields before they're parsed — add the parser stage first
- Assuming a field visible in Grafana Explore is a stream label — check with `gcx logs labels -d '<loki-uid>'` (only shows stream labels)

---

## Interpreting Graph Output

`-o graph` renders an ASCII time-series chart in the terminal. Key patterns:

| Visual Pattern | Likely Cause |
| --- | --- |
| Sudden vertical spike | Deployment, config change, or external event |
| Gradual rising trend | Resource accumulation (memory leak, disk fill) |
| Flat high value | Persistent overload or misconfiguration |
| Periodic spikes | Cron job, scheduled task, or traffic surge |
| Drop to zero then spike | Process restart or deployment rollout |
| Sawtooth pattern | Crash-loop or auto-scaling oscillation |

For a Prometheus matrix response, use `-o json` to extract exact values:

```bash
# Get the peak value during the alert window
gcx metrics query -d '<datasource-uid>' '<query>' --from now-2h --to now --step 1m -o json | \
  jq '[.data.result[].values[][1] | tonumber] | max'
```

---

## Runbook Fetching

If the alert annotation contains a GitHub runbook URL, fetch it with:

```bash
gh api '/repos/<owner>/<repo>/contents/<path>' --jq '.content' | base64 -d
```

For non-GitHub URLs, use `curl`:

```bash
curl -s "<runbook_url>"
```

---

## Setup reference

- [`tools/gcx/README.md`](../../../tools/gcx/README.md) for operator-managed gcx setup; do not change configuration during triage.
