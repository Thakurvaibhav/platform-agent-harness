# Worked Example: Alert Investigation

End-to-end RCA of a firing alert using the `gcx` skill bundle, cross-signal queries, and `bd remember` to capture the root cause for future sessions.

Placeholders are generic: `<service>`, `<cluster>`, `<datasource-uid>`.

---

## 0. Initial trigger

User in the main session:

> "PagerDuty just paged me for `<service>HighErrorRate`. Can you investigate?"

The `investigate-alert` skill (from the `gcx` bundle) is the right entry point. Main session activates it.

## 1. Locate the alert

```bash
rtk gcx --agent alert rules list -o json | \
  jq '.[] | .rules[]? | select(.name == "<service>HighErrorRate")'
```

Result includes: `state: firing`, `health: ok`, `labels.cluster=<cluster>`, `annotations.runbook_url`, `annotations.dashboard_url`, `datasourceUid`.

## 2. Early-exit checks

- `type` is `alerting` (not `recording`) — continue.
- `state` is `firing` — full investigation needed.

## 3. Query the underlying metric

From the alert's `expr`:

```
sum by (cluster) (rate(http_requests_total{job="<service>",status=~"5.."}[5m]))
  / sum by (cluster) (rate(http_requests_total{job="<service>"}[5m]))
  > 0.02
```

Run it to see the current value and trend:

```bash
rtk gcx --agent metrics query -d <datasource-uid> \
  'sum by (cluster) (rate(http_requests_total{job="<service>",status=~"5.."}[5m]))
     / sum by (cluster) (rate(http_requests_total{job="<service>"}[5m]))' \
  --from now-2h --to now --step 1m -o graph
```

Error ratio is ~5%, started ~25 min ago, sustained.

## 4. Break down by dimension

Find the bad actor — by endpoint, status code, instance:

```bash
rtk gcx --agent metrics query -d <datasource-uid> \
  'sum by (status) (rate(http_requests_total{job="<service>",status=~"5.."}[5m]))' \
  --from now-1h --to now --step 1m -o json

rtk gcx --agent metrics query -d <datasource-uid> \
  'sum by (handler) (rate(http_requests_total{job="<service>",status=~"5.."}[5m]))' \
  --from now-1h --to now --step 1m -o json
```

The error is concentrated on `status=504` and `handler=/api/v1/widgets`. Suggests upstream timeout on one endpoint.

## 5. Correlate with logs

Switch to the `debug-with-grafana` skill's log step:

```bash
rtk gcx --agent logs query -d <loki-uid> \
  '{job="<service>"} |~ "timeout|deadline exceeded|context canceled"' \
  --from now-1h --to now -o json
```

Found ~200 lines/min of `context deadline exceeded` from the `<widgets-db>` client, all from `/api/v1/widgets` paths.

## 6. Check the upstream

```bash
rtk gcx --agent metrics query -d <datasource-uid> \
  'histogram_quantile(0.95, rate(db_query_duration_seconds_bucket{client="<service>",db="<widgets-db>"}[5m]))' \
  --from now-2h --to now --step 1m -o json

rtk gcx --agent metrics query -d <datasource-uid> \
  'pg_stat_activity_count{datname="<widgets-db>"}' \
  --from now-2h --to now --step 1m -o json
```

P95 query latency for `<widgets-db>` jumped from 50ms to 4s ~30 min ago. Active connection count tripled.

## 7. Recent changes

```bash
rtk gh pr list --base main --state merged --limit 20 \
  --json mergedAt,title,labels,number \
  --search "label:database OR label:<service>"
```

A migration PR on `<widgets-db>` merged 35 min ago — adds a non-indexed column to a hot table.

## 8. Root cause

The migration added a column without an index. Now-required full table scans drive query latency to 4s, which exceeds the 1s client timeout, which surfaces as `504` on `/api/v1/widgets`.

## 9. Output to user

```
Alert: <service>HighErrorRate
State: firing in <cluster>
Monitors: 5xx error ratio over rolling 5m

Current value: ~5%  |  Started: ~25 min ago  |  Trend: sustained
Concentrated on: handler=/api/v1/widgets, status=504

Likely cause:
- <widgets-db> p95 query latency jumped 50ms → 4s ~30 min ago.
- Active connections tripled.
- A schema migration adding a non-indexed column to a hot table merged 35 min ago.

Impact: ~5% of widget API requests failing in <cluster>.

Runbook: <annotations.runbook_url>
Dashboard: <annotations.dashboard_url>

Recommended next actions:
1. Add an index on the new column. Lowest-risk fix; targets root cause.
2. Roll the column non-null default change forward without the index? — no, latency stays bad.
3. Temporary fix: revert the migration. Higher risk if data has already been written.

Recommend creating an incident — customer impact is confirmed.
```

## 10. Persist the learning

Before closing the session:

```bash
bd remember "<widgets-db> schema migration without index causes <service> 504 storm via 4s query latency exceeding 1s client timeout. Always require explicit index review on hot tables." \
  --key <repo>/lesson/<widgets-db>-migration-index

bd remember "<service>HighErrorRate alert: when it fires, check db_query_duration_seconds_bucket{db=<widgets-db>} p95 first — fastest signal." \
  --key <repo>/trouble/<service>-error-rate-rca
```

Add a line to [`agent-knowledge/references/log.md`](../agent-knowledge/references/log.md):

```
## [2026-05-24] bugfix | <repo> | <service> 504 storm — root cause: unindexed migration on <widgets-db> [bd:<id>]
```

## 11. Followups

If a fix PR is in scope:

- Dispatch `task-planner` to break down (index migration + rollback safety).
- `helm-engineer` is not involved — DB schema lives in a separate repo.
- `pr-reviewer` is dispatched for the index-add PR.

If not, hand the report to the on-call human and stop.

## 12. Compaction

If this session needs to continue past the context threshold:

- `ctx-threshold-warn.py` nudges `/compact`.
- `pre-compact-bd-sync.py` captures the `<service>HighErrorRate` finding, runbook link, and dashboard link into `session/pre-compact`.
- Next session, `bd prime` surfaces the two memories above. No re-investigation needed.

---

## What this exercised

- `investigate-alert` and `debug-with-grafana` bundled skills (no harness vendoring).
- Cross-signal RCA: metrics → logs → upstream → recent changes.
- `rtk` for verbose `gcx` queries.
- `bd remember` capturing two distinct learnings (`lesson/...` and `trouble/...`).
- The compaction lifecycle preserving the RCA across context resets.

Three signals, one root cause, two durable memories, one alert quieted.
