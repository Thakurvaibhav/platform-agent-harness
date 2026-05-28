# Observability Learnings

Numbered, append-only. **Update the existing entry — never duplicate.**

## PromQL & rate intervals

1. **Always verify metric names exist before writing alerts.** A typo silently produces a no-op alert that never fires. Verify with:
   ```bash
   curl -s <pod-ip>:<port>/metrics | grep <metric>
   ```
   or:
   ```bash
   rtk gcx --agent metrics query -d <prom-uid> '<metric_name>' --since 5m -o json
   ```

2. **`$__rate_interval` fails with 60s scrape intervals.** With a 60s scrape interval, Grafana's `$__rate_interval` resolves to ~60s, which yields only 1 data point — `rate()` needs at least 2 samples. Use a hardcoded `5m` rate window for any datasource with a 60s scrape interval.

3. **Prefer a custom `$rate_interval` Grafana variable over hardcoded windows.** Add a Grafana custom variable (options: `1m,5m,10m,15m`; default `5m`) rather than hardcoding `[5m]` in every query. Avoids the auto-scaling problem in learning #2 while giving operators flexibility.

## PromQL aggregation & joins

4. **Bare aggregations drop labels.** `min(metric)` without a `by` clause drops every label, leaving `{{ $labels.cluster }}` empty in the rendered annotation. Always use `min by (cluster, environment) (metric)` (or similar).

5. **`sum by(...)` clauses are mandatory when labels are referenced in annotations.** Stripping a label that the annotation template uses leaves a literal `{{ $labels.foo }}` in the rendered alert.

6. **PromQL `on()` joins must include `cluster` in multi-cluster setups.** `/ on(namespace, pod, container)` drops the `cluster` label. Always use `/ on(cluster, namespace, pod, container) group_left`.

7. **Scope queries with `cluster="<name>"` label.** Multi-cluster Thanos / Mimir / VictoriaMetrics deployments will otherwise merge series across clusters and produce misleading aggregates.

## Alert design

8. **Prefer ratios over absolute thresholds.** `errors/total > 0.02` survives traffic changes; `errors > 100` does not. Resource alerts should compare against request/limit ratios rather than raw byte thresholds.

9. **CPU throttling: use CFS period ratios, not CPU vs limit.** `rate(container_cpu_cfs_throttled_periods_total[5m]) / rate(container_cpu_cfs_periods_total[5m])` directly measures the scheduler denying CPU time. Comparing CPU usage to limit is a proxy that misses bursts.

10. **`absent()` alerts catch silent failures.** When a metric exists, downstream alerts work. When it doesn't (target removed, scrape config broken, exporter crashed), nothing alerts unless `absent({...}) == 1` is also configured.

11. **SLO error and total queries MUST contain the literal `{{.window}}` placeholder.** Helm does not process strings inside values files; the SLO chart performs the substitution at template time. Hard-coding a window (e.g. `[5m]`) breaks multi-window SLO calculations.

## ServiceMonitor & ingestion

12. **ServiceMonitor selector mismatch is the #1 cause of "metrics not in Prometheus".** The ServiceMonitor's `selector` must match the Service labels exactly. Verify with:
    ```bash
    kubectl get svc -n <ns> --show-labels
    kubectl get servicemonitor -n <ns> -o yaml | yq '.items[].spec.selector'
    ```

13. **Recording rule outputs take 1–2 minutes to appear** after creation. SLO statuses showing NODATA immediately after creation are usually slow propagation, not configuration errors.

## Grafana dashboards

14. **`label_values()` and Prometheus `external_labels`.** `label_values(some_metric, cluster)` fails when `cluster` is added by Prometheus `external_labels` rather than carried on the metric. Use `label_values(up{job="..."}, cluster)` since `up` always carries external labels.

15. **Grafana import may fail with 403.** The API token may lack folder-level permissions. Fall back to providing JSON for manual UI import.

16. **Dashboard conventions.** Store dashboards in `artifacts/grafana-dashboards/`. Include the standard template variables: `datasource`, `cluster`, `namespace`, `pod`. Use `graphTooltip: 1` (shared crosshair). Verify the namespace in each query matches the actual deployment namespace.

## Metric label differences

17. **HTTP metrics from different collectors use different label names but identical values.** Auto-instrumentation tools (Beyla and similar) emit `k8s_namespace_name` / `service_name`. Service meshes (Istio and similar) emit `source_workload_namespace` / `source_workload`. The values are identical strings (both derived from the same K8s objects), so Grafana dashboard variables can be shared across metric sources — just use the appropriate label name per query.
