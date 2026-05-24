# Observability Learnings

Numbered, append-only. **Update the existing entry — never duplicate.**

1. **Always verify metric names exist before writing alerts.** A typo silently produces a no-op alert that never fires. Verify with:
   ```bash
   curl -s <pod-ip>:<port>/metrics | grep <metric>
   ```
   or:
   ```bash
   rtk gcx --agent metrics query -d <prom-uid> '<metric_name>' --since 5m -o json
   ```

2. **Use `sum by(...)` clauses to preserve labels** referenced in annotations. Stripping a label that the annotation template uses leaves a literal `{{ $labels.foo }}` in the rendered alert.

3. **Scope queries with `cluster="<name>"` label.** Multi-cluster Thanos / Mimir / VictoriaMetrics deployments will otherwise merge series across clusters and produce misleading aggregates.

4. **Prefer ratios over absolute thresholds** where possible. `errors/total > 0.02` survives traffic changes; `errors > 100` does not.

5. **SLO error and total queries MUST contain the literal `{{.window}}` placeholder.** Helm does not process strings inside values files; the SLO chart performs the substitution at template time. Hard-coding a window (e.g. `[5m]`) breaks multi-window SLO calculations.

6. **`absent()` alerts catch silent failures.** When a metric exists, downstream alerts work. When it doesn't (target removed, scrape config broken, exporter crashed), nothing alerts unless `absent({...}) == 1` is also configured.

7. **ServiceMonitor selector mismatch is the #1 cause of "metrics not in Prometheus".** The ServiceMonitor's `selector` must match the Service labels exactly. Verify with:
   ```bash
   kubectl get svc -n <ns> --show-labels
   kubectl get servicemonitor -n <ns> -o yaml | yq '.items[].spec.selector'
   ```

8. **Grafana import may fail with 403.** The API token may lack folder-level permissions. Fall back to providing JSON for manual UI import.

9. **Recording rule outputs take 1–2 minutes to appear** after creation. SLO statuses showing NODATA immediately after creation are usually just slow propagation, not configuration errors.
