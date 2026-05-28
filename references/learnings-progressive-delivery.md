# Progressive Delivery Learnings

Argo Rollouts + Gateway API plugin patterns, pitfalls, and ArgoCD integration. Numbered, append-only. **Update the existing entry — never duplicate.**

## Gateway API plugin (`argoproj-labs/gatewayAPI`)

1. **`httpRouteSelector` does NOT support header-based routing.** The plugin hardcodes `UseHeaderRoutes: false` for routes discovered via `httpRouteSelector`. `setHeaderRoute` silently no-ops (returns success without patching the HTTPRoute). Selector-based discovery only supports weight management. For header-based canary, use explicit `httpRoutes` with `useHeaderRoutes: true`. Applies to all plugin versions since v0.7.0.

2. **`managedRoutes` is required for `setHeaderRoute`.** The Rollout spec must declare `trafficRouting.managedRoutes` listing every header route name used in `setHeaderRoute` steps. Without it: `InvalidSpec: missing field spec.strategy.canary.trafficRouting.managedRoutes`.

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

9. **`workloadRef` vs inline pod template.** `workloadRef` references an existing Deployment's pod template — useful when you can't modify the upstream chart. Inline template (conditional Rollout-OR-Deployment) is cleaner for charts you control — no `scaleDown` complexity, no Deployment replicas drift, no controller conflict.

10. **Triggering a canary with `workloadRef`.** `kubectl argo rollouts restart` does NOT trigger a canary — it just cycles pods within the current revision. To trigger a canary, change the referenced Deployment's pod template (e.g. patch an annotation). The Rollout detects the template change and creates a new revision.

11. **Abort state is sticky.** After `kubectl argo rollouts abort`, the Rollout stays Degraded until a new spec change triggers a new revision. `retry`, `undo`, and `promote --full` do not reliably clear the abort state. Clean approach: remove overrides, let ArgoCD prune the Rollout, then re-enable for a fresh revision 1.
