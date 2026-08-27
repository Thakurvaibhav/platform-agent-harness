# Observability Learnings

Numbered, append-only. **Update the existing entry — never duplicate.**

See also: `learnings-envoy-gateway.md`, `learnings-workload-debug.md`, `learnings-istio.md`

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

## PromQL & rate intervals (continued)

18. **`increase()` extrapolates to the full window edges — never grade an integer-valued counter delta against an integer threshold using it.** Prometheus scales the observed rise proportionally to cover the whole requested window, so a counter that moved by exactly an integer amount reports a non-integer value close to but not equal to it (a true delta of 3 can report as 3.21). A check with an integer threshold ("more than 2", "3 or more") then produces a value sitting between the two branches, and two structurally-equivalent checks measuring the same real event can disagree on the verdict purely from extrapolation noise. For an exact integer delta, use `max_over_time(X[w]) - min_over_time(X[w])` instead — it reads the same series without boundary extrapolation. Caveat: the exact form reads a single series identity, so it under-counts (never over-counts) if the underlying series is replaced mid-window (e.g. a workload restart that changes an instance label starts a new series from zero) — pair it with an independent cross-check when that distinction matters.


## PromQL aggregation & joins (continued)

19. **Every label named in a PromQL join's `on(...)` clause must also appear in the `by(...)` of EACH aggregation feeding that join, or the join can never match — and this fails silently as a permanently-empty result, not as an error.** A `sum by (a, b, c)` feeding a join written as `and on (cluster, a)` will never match anything if the `by` clause drops `cluster`, because the aggregation itself already discarded the label the join needs — the query returns empty for every input, forever, while a naive "did this arm at least once" check on either individual operand can still report armed (each operand individually is non-empty; only the *joined* expression is empty). Discriminate this class by running the identical query with and without the missing label in `by()`, holding everything else constant — a jump from zero rows to non-zero rows on that one token change is the proof. General fix pattern: your arming/liveness proof should run the FULL composed expression with only the graded condition removed, not just check that each operand independently returns data — per-operand arming checks structurally cannot catch a broken join key.

20. **PromQL vector arithmetic propagates emptiness — one empty operand deletes the ENTIRE expression it's part of, including any arming/liveness proof riding on the same expression.** If a ratio's denominator is itself a sum of two series (e.g. `opened_total + failed_total`) and one of those two has simply never emitted a sample for the slice you're querying, the vector addition returns completely empty — not zero, empty — and that silently deletes the whole downstream expression, including any check meant to prove the query is "armed" (returning data at all). Guarding only the operand you suspect can be sparse is not enough: every operand in the expression that CAN independently be lazy needs an `or (<operand> * 0)`-style guard (or your engine's equivalent "coalesce with zero" idiom), not just the one you think is the risky one. Verify by comparing an unguarded version (empty), a guarded version (reads zero correctly), and an already-known-good control (matches to several significant figures).


## Verification traps (metrics, logs, shell)

21. **A metric appearing in the store's metric-NAME index is not proof that it has any live series — and this failure class is strictly more dangerous than a metric that doesn't exist at all, because it looks reassuring instead of obviously broken.** A metric name can be indexed while carrying zero actual time series — commonly because an exporter's own allowlist drops the series even though the metric name is still known to the store from another target or a historical scrape. A check written as `count(metric{...} == 0)` then returns empty and reports "nothing bad found" forever, and a reviewer who checks "does this metric name exist" and stops there will be satisfied by exactly the broken case. Always verify a non-zero SERIES count over the time window and label scope you actually care about — never metric-name-index membership — and check more than one target/instance, since a single healthy instance can mask the rest being silently absent.


## PromQL & rate intervals

22. **Both `increase()` and the "current minus (current offset window)" pattern are wrong ways to difference two counter readings when the underlying series set churns — use `sum(max_over_time(X[w]) - min_over_time(X[w]))` instead.** Measured side by side on a real counter-differencing task where the true delta was a small negative residual: the three methods disagreed by an order of magnitude (`increase()` and the offset-subtraction form were both off by roughly 10x from the correct value). `increase()` boundary-extrapolates (a separate, always-present error); the offset-subtraction form additionally breaks whenever the series set changes across the window boundary — e.g. pods being replaced mid-window mean the two endpoints are literally not measuring the same set of series. That churn is exactly the condition you're most likely to be measuring under (a rolling deploy, a scale event), which is precisely when this bug bites hardest. The `max_over_time - min_over_time` form is computed per-series and survives that churn.

23. **Subtracting two `increase()` values COMPOUNDS their extrapolation error instead of cancelling it — do not assume the errors on both sides of a subtraction wash out.** Comparing `increase(counter_a) - increase(counter_b)` when the two true counts are actually equal can still produce a nonzero result, because each `increase()` is independently boundary-extrapolated in its own direction — two true counts of 412 each can render as, say, 413.2 and 411.8, giving a difference of 1.4 where the true difference is exactly 0. A delta rule with no tolerance then manufactures a false alarm on a perfectly healthy system. Use exact deltas (`max_over_time - min_over_time`, or a same-series offset-subtraction where series identity is stable) on BOTH sides of any counter subtraction, not just one. Exception worth keeping: `increase()` IS safe under a bare `> 0` predicate, because `increase()` is exactly zero if and only if the true delta is zero — extrapolation cannot flip that boolean. So an "did anything happen at all" check can keep using `increase()`; a magnitude comparison or a difference between two counters may not.


## Verification traps (metrics, logs, shell)

24. **`kubectl <list-command> --no-headers 2>&1 | wc -l` returns 1 on an EMPTY result, not 0.** `kubectl` writes its "No resources found" message to STDERR (not stdout) and exits 0, so folding stderr into stdout with `2>&1` turns a genuine zero-objects result into a line count of one — a phantom finding on a perfectly clean cluster. The fix is not simply `2>/dev/null` (which silently discards a real error too); prefer `-o json` piped into a real JSON parser and count the `items` array — the count then comes from parsed structure, so stderr cannot contaminate it, and the same pass gives you the structured data you usually need anyway. Audit for this specific pattern whenever a shell-based validation script reports a suspicious exact count of 1.

25. **Querying a metrics or log time-series store with an `endTime` that is still in the future silently UNDER-FILLS the result — no error, no warning, just a plausible-looking wrong number.** A range query with `endTime` set even a few minutes ahead of the actual wall clock returns a result stamped at that future timestamp but computed over only the portion of the window that has real data — which can under-report a rate by a large margin (a measured case: a 30-minute-window rate query returned roughly 60% of the correct value when `endTime` was 12 minutes ahead of the clock). A related, easy-to-misread symptom: an instant query at a future `endTime` can return data while a range query over an overlapping strictly-past interval returns nothing, making a perfectly healthy metric look intermittent. Rule: before any measurement pass, read the actual wall clock and set BOTH window edges strictly in the past (`endTime <= now - one scrape interval`) — never trust a mental estimate of elapsed time, especially in a long working session. Detection if you suspect this already happened: cross-check the same quantity at two different window lengths; if they disagree by more than normal diurnal variation, one of them was short-filled.

---
