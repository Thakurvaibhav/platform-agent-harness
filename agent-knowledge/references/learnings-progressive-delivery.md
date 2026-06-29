# Progressive Delivery Learnings

Argo Rollouts + Gateway API plugin patterns, pitfalls, and ArgoCD integration. Numbered, append-only. **Update the existing entry — never duplicate.**

See also: `learnings-argocd.md`, `learnings-helm-ci.md`, `learnings-code-review.md`

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

26. **jq `del()` is INVALID for nested-array paths — ArgoCD gotcha.** ArgoCD wraps `jqPathExpressions` in `del()`, and `del(.spec.rules[].backendRefs[].weight)` is invalid jq for nested arrays (upstream issue #26870, OPEN). Use `walk(if type=="object" and has("weight") then del(.weight) else . end)` or explicit `jsonPointers`.

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
