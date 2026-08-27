# Progressive Delivery Learnings

Argo Rollouts + Gateway API plugin patterns, pitfalls, and ArgoCD integration. Numbered, append-only. **Update the existing entry — never duplicate.**

See also: `learnings-argocd.md`, `learnings-helm-ci.md`, `learnings-code-review.md`, `learnings-envoy-gateway.md`

## Gateway API plugin (`argoproj-labs/gatewayAPI`)

1. **`httpRouteSelector` does NOT support header-based routing.** The plugin hardcodes `UseHeaderRoutes: false` for routes discovered via `httpRouteSelector`. `setHeaderRoute` silently no-ops (returns success without patching the HTTPRoute). Selector-based discovery only supports weight management. For header-based canary, use explicit `httpRoutes` with `useHeaderRoutes: true`. Applies to all plugin versions since v0.7.0.

2. **`managedRoutes` is required for `setHeaderRoute`.** The Rollout spec must declare `trafficRouting.managedRoutes` listing every header route name used in `setHeaderRoute` steps. Without it: `InvalidSpec: missing field spec.strategy.canany.trafficRouting.managedRoutes`.

3. **`setCanaryScale` requires `trafficRouting`.** Using `setCanaryScale` without `trafficRouting` causes `InvalidSpec: SetCanaryScale requires TrafficRouting to be set`. When traffic routing is disabled, use plain `setWeight` steps instead.

4. **Plugin v0.13.0 requires Gateway API v1.2+.** The refactored header routing uses the `name` field on HTTPRoute rules (introduced in Gateway API 1.2) instead of ConfigMap tracking. The ConfigMap is no longer needed and can be deleted.

5. **Plugin v0.13.0 `in-progress` label.** The plugin adds `rollouts.argoproj.io/gatewayapi-canary: in-progress` to HTTPRoutes during active canary and removes it when stable returns to 100%. Introduced in v0.9.0 for ArgoCD drift avoidance.

6. **Upstream chart renders empty `annotations:` on Services.** The argo-rollouts chart (2.40.9) unconditionally renders a bare `annotations:` key on Service templates. The API server normalizes this away, causing a perpetual ArgoCD OutOfSync diff. Fix: set `serviceAnnotations` with a real value (e.g. `app.kubernetes.io/managed-by: argo-rollouts-chart`).

## ArgoCD integration

7. **Per-Application `ignoreDifferences` with `select()` on plugin labels doesn't work.** The plugin adds the `in-progress` label AND modifies `.spec.rules`. If only `.spec.rules` is ignored (with `select()` on the label), ArgoCD sees the label itself as a diff and reverts the entire resource, removing both label and rules. Fix for per-app: ignore both the label (`jsonPointers: /metadata/labels/rollouts.argoproj.io~1gatewayapi-canary`) and rules (`jqPathExpressions: .spec.rules`). For production: use ArgoCD CM-level `resource.customizations.ignoreDifferences` which evaluates during normalization and handles this correctly.

8. **Required `ignoreDifferences` for Rollout-managed resources.** Three resource types need ignore entries:
   - **Deployment** `/spec/replicas` (when using `workloadRef` with `scaleDown: onsuccess`)
   - **Service** `/spec/selector/rollouts-pod-template-hash` (Rollout controller adds hash to selector)
   - **HTTPRoute** `.spec.rules` + `/metadata/labels/rollouts.argoproj.io~1gatewayapi-canary` (plugin modifies rules and adds label during canary)

## Rollout patterns

9. **`workloadRef` is the correct approach for existing Deployments.** `workloadRef` with `scaleDown: onsuccess` is required when you want Deployment and Rollout to coexist during migration. The controller reads the Deployment's pod template, creates its own ReplicaSet, and scales the Deployment to 0 once stable. With inline template, the Rollout has NO relationship to the Deployment — it won't scale it down, resulting in 2x pods. Inline template only makes sense if you suppress the Deployment from rendering (hard cutover).

10. **Triggering a canary with `workloadRef`.** `kubectl argo rollouts restart` does NOT trigger a canary — it just cycles pods within the current revision. To trigger a canary, change the referenced Deployment's pod template (e.g. patch an annotation). The Rollout detects the template change and creates a new revision.

11. **Abort state is sticky.** After `kubectl argo rollouts abort`, the Rollout stays Degraded until a new spec change triggers a new revision. `retry`, `undo`, and `promote --full` do not reliably clear the abort state. Clean approach: remove overrides, let ArgoCD prune the Rollout, then re-enable for a fresh revision 1.

12. **Rollout template must guard on `deployment.enabled`.** Since `workloadRef` references the Deployment, the Rollout template must also check that the Deployment renders. Without this, enabling `rollout.enabled` with no Deployment produces a Rollout pointing at nothing.

13. **Promotion modes + steps override pattern.** Three modes with escape hatch. If `rollout.steps` is non-empty, render those directly. Otherwise: **auto** = OMIT `steps` entirely, use `maxSurge`/`maxUnavailable` (true rolling update). **soak/manual with trafficRouting** = (1) `setCanaryScale: {replicas: max(3, ceil(replicas/4))}`, (2) `setHeaderRoute`, (3) pause (timed/indefinite), (4) `setCanaryScale: {matchTrafficWeight: true}`, (5) progressive weight ramp. Key insight: `steps: [{setWeight: 100}]` is instant cutover, NOT rolling update — omit steps entirely for true rolling.

14. **Values key naming: use `trafficRouting` not `httpRoute`.** The values key controlling Rollout's Gateway API traffic routing should be `rollout.trafficRouting.enabled`, NOT `rollout.httpRoute.enabled`. The latter sounds like it toggles HTTPRoute rendering; the former correctly describes what it does.

15. **Deployment replicas stuck at 0 after rollout disable with `ignoreDifferences`.** When a Rollout uses `workloadRef` and `scaleDown: onsuccess`, disabling leaves the Deployment at `replicas: 0`. ArgoCD `ignoreDifferences` on `spec.replicas` prevents reconciliation. Fix: `kubectl scale` or temporarily remove ignoreDifferences; HPA will restore once Rollout is removed.

16. **Gateway API plugin `httpRoutes` entries must NOT include a `namespace` field.** The plugin discovers HTTPRoute resources by label selector, not namespace lookup. Including a `namespace` field causes route discovery failures. Use only `name` and `useHeaderRoutes: true`.

17. **Envoy Gateway returns hard 503 when no endpoints exist.** EG produces 503 with response flags NH/NC when a backend has zero ready endpoints. During canary rollouts, the Service backing the canary MUST always have ready endpoints for the duration of the traffic split.

18. **Argo Rollouts Experiment CRD is single-shot with hours-format duration.** `spec.duration` accepts hours format (e.g., `120h` = 5 days). Experiments are SINGLE-SHOT — re-run requires a name change (use date suffix). Controller GCs the experiment's ReplicaSets on duration expiry.

19. **With workloadRef, rollout.yaml needs NO pod template.** The Rollout references the Deployment's pod template — it does NOT duplicate it. The rollout.yaml should be slim: metadata + selector + workloadRef + strategy.canary.

20. **Deployment MUST gate `spec.replicas: 0` when rollout.enabled.** With `RespectIgnoreDifferences=false`, ArgoCD keeps re-applying `replicas: N` from the chart, overriding the `scaleDown:onsuccess` state. Fix: gate in deployment.yaml `{{- if ($component.rollout).enabled }} replicas: 0 {{- else }} ...`. Setting `replicas: 0` in the chart is GitOps-correct because the Rollout controller owns replicas when `workloadRef` is active.

21. **HPA must target the Rollout (not Deployment) when `workloadRef`+`scaleDown:onsuccess`.** After first successful promotion, the Deployment's `spec.replicas` goes to 0. An HPA still targeting the Deployment sees 0, falls below `minReplicas`, and fights the Rollout controller. Fix: conditionally set `scaleTargetRef` to `Rollout` when `rollout.enabled`.

22. **`canaryService`/`stableService` must be conditional on the Service rendering.** For workloads where container ports may not be defined, the Service guards on `$serviceEnabled && $containerPorts`. The Rollout template must apply the same guard, otherwise it references non-existent Services.

## HTTPRoute and canary routing

23. **Gateway API `HTTPRoute.spec.rules` is hard-capped at `maxItems: 16`.** Overflow rejects the WHOLE route. Fix: split into a second HTTPRoute that OMITS `parentRefs`/`hostnames` — it inherits the same listener. EG flattens all HTTPRoutes on a listener into one rule list and sorts by specificity regardless of source route. Offline proof: render before/after and assert order-normalized UNION is byte-identical.

24. **Route-split is behavior-preserving — conditions and proof.** EG sorts rules by: path-type (Exact>Regex>Prefix), path char count, #header, #exact-header, #cookie, #query. Source-HTTPRoute identity does NOT affect ordering. The ONLY delta: rules that tie on ALL sort keys break by creationTimestamp/namespace/name (cross-route) post-split vs rule-list-index (intra-route) pre-split. GitOps bulk-apply gives same creationTimestamp, so split route NAMES must preserve original rule order for tied-overlapping pairs.

25. **ArgoCD ignoreDifferences jq guard must use a STATIC chart label, not a controller-toggled label.** The guard must evaluate identically on git-desired and live (symmetric). A guard on a static `canary-traffic-managed` label is symmetric; a guard on the controller's `in-progress` label is asymmetric (causes the incident). For multi-rule routes (plugin v0.15.0+), use `startswith("canary-header")` not exact match — covers indexed names (`canary-header-1`, etc.).

26. **jq `del()` is INVALID for nested-array paths — ArgoCD gotcha.** ArgoCD wraps `jqPathExpressions` in `del()`, and `del(.spec.rules[].backendRefs[].weight)` is invalid jq for nested arrays (upstream issue argoproj/argo-cd#26870, OPEN). Use `walk(if type=="object" and has("weight") then del(.weight) else . end)` or explicit `jsonPointers`.

27. **jq CAN ignore a SINGLE element of an atomic list.** `HTTPRoute.spec.rules` is `listType: atomic`, but `jqPathExpressions: '.spec.rules[] | select(.name == "canary-header")'` correctly removes ONLY the named rule from the diff. Atomic-list semantics block partial SSA MERGE, not jq-based diff suppression.

28. **`setHeaderRoute` managed route is REMOVED when canary RS has 0 available replicas** (argo-rollouts v1.9.0 source, `rollout/trafficrouting.go` L199-269). The route is never re-added because `SetHeaderRoute` only re-fires on a `setHeaderRoute` step. Failure trap: `setCanaryScale: {matchTrafficWeight: true}` at weight=0 un-pins the canary, scales to 0, triggers removal. **FIX: order `setWeight: N>0` BEFORE any `matchTrafficWeight` step.**

29. **HTTPRoute `spec.rules` field-manager is `gatewayAPI`, not `rollouts-controller`.** The plugin does a full PUT with no explicit FieldManager, but apiserver populates `managedFields` as `manager='gatewayAPI'`. A `managedFieldsManagers` ignore is fragile (name is User-Agent-derived, `spec.rules` is atomic, and it breaks GitOps route-edit visibility). Use the static-label jq guard instead.

30. **Argo Rollouts keeps canary Service pointed at STABLE pods when idle.** `rollouts-pod-template-hash` on the canary Service == stable RS hash at rest, same endpoints as stable. So the canary Service is NEVER empty (no 503), and a permanent cohort header rule pointing at the canary Service needs NO warm canary replica.

31. **`setHeaderRoute` with a COOKIE match FAILS on routes that already match cookie.** The plugin copies the base match and APPENDS the setHeaderRoute match; if the base already matches `cookie`, the result has two `cookie` headers in one match — Gateway API rejects `Duplicate value: {name: cookie}`. Use a non-cookie signal for canary routing on cookie-matching routes.

## GitOps-friendly alternatives

32. **GitOps-friendly alternatives to controller-mutated HTTPRoute canary.** (1) STATIC PINNING: separate static HTTPRoutes for stable+canary, Rollout manages only weight. (2) Unconditional weight ignore + `ApplyOutOfSyncOnly=true`. (3) **Flagger**: AVOIDS drift BY DESIGN (generates HTTPRoute at runtime with ownerReferences, never in git). (4) Structural root cause: one object both declared in git AND mutated by a controller; fix by making them different objects.

33. **Two-layer ArgoCD deploy for canary + app-of-apps cascade.** The `ignoreDifferences` lives on the APPLICATION object (rendered by app-of-apps), while route labels + rollout config come from the app SOURCE chart. To test a branch, repoint the app-of-apps at the branch (cascades both layers). ORDER matters: the safe ignore must be live BEFORE the canary runs.

## Helm and chart patterns

34. **Helm `default` filter treats 0 as falsy.** `{{ .maxUnavailable | default "25%" }}` replaces explicit `0` with `"25%"`. Use `kindIs "invalid"` check instead: `{{- if not (kindIs "invalid" .maxUnavailable) }}{{ .maxUnavailable }}{{- else }}"25%"{{- end }}`.

35. **Helm route-split surgical-edit techniques (behavior-preserving).** (a) Don't `yaml.safe_load`+`safe_dump` already-scrutinized values files — it reformats flow style, re-quotes regex matches, drops comments. Use LINE-SPAN SURGERY: parse by indentation, extract rule source lines verbatim, re-emit as N single-rule routes. (b) `ruamel` gotchas: reusing same object reference across split children emits YAML anchors — `copy.deepcopy` every moved subtree. (c) Behavior-preservation proof = MATCH-TUPLE UNIQUENESS across all rendered rules (path.type/value + sorted header tuples + method). (d) Orphan-ref check: after split/rename, grep for old route name in `charts/argo-apps` and Rollout `trafficRouting.httpRoutes` list.

36. **Envoy Gateway inline-Lua edge header injection.** Use `EnvoyExtensionPolicy` kind, `lua.type: Inline`; reads/mutates request headers. Attach at GATEWAY scope for anything that must run BEFORE routing. EG's default filter order places EEP-Lua AFTER ext_authz BEFORE router. Envoy Lua `clear_route_cache` defaults true, so header mutation auto-clears route cache for re-evaluation.

37. **HTTPRoute else-hardcoded-defaults footgun in templates.** Templates that emit hardcoded labels ONLY in the `{{else}}` branch (no explicit `labels` block) silently DROP those defaults when any `labels` block is added. ALWAYS render before/after and diff the label set per route.

38. **Argo Rollouts default `progressDeadlineAbort: false` → a stuck canary hangs in Degraded/Timeout INDEFINITELY.** A chart that omits `spec.progressDeadlineAbort` gets the `false` default → a canary that exceeds `progressDeadlineSeconds` (600s default) does NOT auto-revert to stable; it hangs, needs a manual `kubectl argo rollouts abort <ro> -n <ns>`, AND re-sticks on every image-updater push. Common trigger: canary pods unschedulable (node group at max size + affinity). Durable fix: `spec.progressDeadlineAbort: true` (validate the retry cadence in dev first) so stuck canaries auto-abort to stable. Stuck-rollout metric phase = `Timeout`.

39. **An alert whose "bad" phase set includes `Abort` can NEVER be cleared by the abort remediation — and abort IS the safe state.** If a degraded-rollout alert matches `rollout_phase{phase=~"Error|Timeout|Abort"}`, the standard remediation `kubectl argo rollouts abort` transitions the phase `Timeout→Abort`, which the alert ALSO matches → it re-fires on `Abort` instead of resolving. But an aborted rollout has reverted to the stable ReplicaSet = safe/serving. Fix: alert on `Error|Timeout|InvalidSpec` only (drop `Abort`) so an abort clears the page; pair with `progressDeadlineAbort: true` (#38) for auto-revert (a brief `Timeout` page, then self-clears). `Abort` can also come from a failed `AnalysisRun`.

## Argo Rollouts metrics, dashboards & alerting

40. **Argo Rollouts exposes two different phase enums that look interchangeable but aren't — a Prometheus metric named `rollout_phase` and the Rollout object's own `.status.phase` use different value sets, and querying one with the other's values silently matches nothing.** At v1.9.0, the `rollout_phase` gauge emits exactly six fixed series per rollout: `Completed|Progressing|Paused|Timeout|Error|Abort` (note `Abort`, not `Aborted`; there is no `Degraded` and no `InvalidSpec` in this enum). The Rollout CR's own `.status.phase` is a smaller, different enum: `Healthy|Degraded|Progressing|Paused`, computed separately by the controller. Concretely: a rollout that exceeded its progress deadline shows object phase `Degraded` via `kubectl`, but the metric emits `rollout_phase{phase="Timeout"}==1` — so an alert meant to catch a stuck rollout must match `Timeout`, and matching `Degraded` against the metric matches nothing at all. The newer replacement metric, `rollout_info`, carries one series per rollout whose value tracks the current phase and adds `InvalidSpec` to its enum — but it has no per-phase label at all, so querying it with a `phase="X"` label selector (as if it behaved like the older metric) also returns nothing. Before writing any Rollout alert, confirm the actual label values live against your own metrics store rather than assuming the CR enum and the metric enum match.

41. **Argo Rollouts' Prometheus metrics carry the CONTROLLER's namespace on the standard `namespace` label, not the workload's — the workload's namespace is a separate `exported_namespace` label, and copying a workload-scoped alert filter onto a rollout metric matches zero series.** Also worth checking before trusting a replica-mismatch alert during a canary: `rollout_info_replicas_desired` reports the full `spec.replicas` (not the canary-scaled count), and the corresponding available-replicas metric reports total available replicas across stable+canary combined — so an `available < desired` alert only produces a false positive during a canary pause if the rollout scales the stable ReplicaSet down below spec (a `dynamicStableScale`-style setting); with the stable ReplicaSet held at full size throughout the canary, total available stays at or above desired the whole time. Verify which scaling mode is in effect before trusting either alert's behavior during a multi-hour manual soak.

42. **An alert that queries a phase-tracking metric by a label the metric doesn't carry can never fire — and the fix must be verified against a live metric store with a negative control before shipping, not assumed correct from documentation.** A query for the replacement metric filtered by a phase label is doubly broken if that metric has no per-phase label at all and the label value used doesn't even exist in the older metric's own enum — confirm both against the live store. Separately, in any alerting chart that renders the PromQL `expr` field through a templating engine but renders `summary`/`description` through a literal string-replace helper, a Prometheus templating variable in the description passes straight through unescaped and must be left as-is — escaping it as if it were the chart's own templating syntax breaks the rendered alert rule. And for a metric that carries no `service` label, don't inherit a file-level alert-group selector that assumes one — match on the metric's actual label set instead of the group's default.

43. **A known HPA/KEDA-vs-canary scale-count oscillation in Argo Rollouts has an upstream fix in flight — worth checking before building a workaround, and worth NOT chasing via a version bump that reverts an earlier, unrelated fix.** `argoproj/argo-rollouts#4847` tracks autoscalers oscillating against a canary because the reported scale-subresource count reflects the wrong replica total during a canary; `argoproj/argo-rollouts#4868` (draft, unmerged as of this writing) adds an opt-in scale-reporting mode that reports only the stable ReplicaSet's count and selector coherently, which is the correct fix for external/object autoscaler metrics (including cron- or queue-based scalers) — a percentage-based canary-scale setting only dampens the oscillation, it doesn't fix it. Before adopting a pre-release version purely to get an in-flight fix, check what else changed in that release line first — a later pre-release can revert an unrelated, already-shipped mitigation the same code area depended on, making "just upgrade" strictly worse than waiting for a stable release. Interim mitigation: avoid pausing a canary on any service whose replica count is driven by an external/absolute autoscaler metric.


## ArgoCD integration (continued)

44. **A prod environment can pin a specific packaged release/distribution tag independently of your GitOps branch — merging to your main branch does not deploy anything until that pinned tag is bumped or a release-branch cherry-pick lands.** This is a distinct failure mode from a stale ArgoCD `targetRevision`: a distribution mechanism that vendors/packages releases into its own channel (e.g. Replicated, or any similar packaged-release tool) can pin its own release-artifact version, so a cluster running under that channel is invisible to a plain `git merge` even when ArgoCD itself is tracking the main branch everywhere else. Before promising a merged change is live on any specific target, check for a pinned release/distribution tag on that target, not just the ArgoCD Application's `targetRevision`.


## Header inspection & canary routing headers

45. **Whether a header is available for HTTPRoute matching is decided entirely by Envoy's filter CHAIN ORDER, not by which filter added the header — confirm order from the live config dump, not from documentation or intent.** A representative chain: an early header-strip filter (removing client-spoofable auth-adjacent headers) runs BEFORE an ext-authz filter, which re-injects trusted values for those same header names, which in turn runs BEFORE the router — so headers injected by ext-authz ARE available for HTTPRoute header-matching, even though a naive reading of "headers were stripped earlier in the chain" would suggest otherwise. The strip-then-reinject pattern exists specifically to prevent client-spoofed values from reaching the authorization filter, not to keep those headers out of routing. Two verification notes: (1) a route's own `requestHeaderModifier` filters run AFTER routing decisions, so headers they add are visible at the backend but were never available for the match that sent the request there — always check a route's own filters, not just the global chain, before asserting what was or wasn't available at match time; (2) when on-the-wire behavior actually matters, a packet capture at the backend is the authoritative source — an L4-only proxy in the path (one that never modifies HTTP headers) means the backend's inbound bytes equal the upstream's outbound bytes, but that equivalence needs to be confirmed for your specific proxy stack, not assumed.

46. **If your application's session already carries a stable identifier in a cookie on every authenticated request, per-tenant or per-user canary routing needs no application change at all — HTTPRoute can match the raw `cookie` header with a regex.** An anchored pattern like `(?:^|;\s*)<key>=<id>(?:;|$)` selects a specific cookie value without a client-side header-injection step; the anchors matter because an unanchored substring match on an id would also wrongly match a longer id that contains it as a prefix. This is complementary to, not a replacement for, an explicit opt-in canary header — cookie matching gives automatic targeting for anyone already carrying that cookie, an opt-in header gives manual per-request control, and a Rollout can use both. One caveat that only bites when combining them: a plugin-managed header-based canary route cannot be layered onto a route that already matches on the `cookie` header — the plugin builds its canary rule by copying the base match and appending its own header match, and Gateway API rejects two `cookie` matches in one rule.
