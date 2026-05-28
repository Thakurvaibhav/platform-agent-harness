# ArgoCD Learnings

Numbered, append-only. **Update the existing entry — never duplicate.**

## Sync & ordering

1. **`ignoreDifferences` requires `RespectIgnoreDifferences=true` in `syncOptions`.** Without this option, ArgoCD still overwrites the live value during sync even though the diff is hidden in the UI. Symptom: live values keep resetting after each sync.

2. **Sync-waves on Application objects only enforce ordering during app-of-apps sync.** They do NOT control when Applications sync their own contents. For guaranteed ordering between independent child Application syncs, use a multi-PR phased approach.

3. **Sync-wave `"5"` is the right default for CRD-dependent resources.** Wave 0 installs the operator and CRDs; wave 5 gives time for CRDs to be Established before the dependent resources sync. Do NOT use `"1"` — too close to default and races with CRD installation.

## Values & naming

4. **Values key naming must be lowercase kebab-case** when keys become Helm release names downstream. Avoid camelCase. Use `index .Values "key-name"` for hyphenated keys in templates.

5. **GKE-targeted ArgoCD apps need a `values/providers/gcp.yaml`.** When an argo-apps entry targets a GKE cluster, always include the GCP provider values file alongside the app entry. Check existing entries for the pattern — omission causes silent platform-detection mismatches downstream.

## Drift & ignoreDifferences

6. **SSA + API-server-injected fields cause sync loops on DaemonSets.** The `deprecated.daemonset.template.generation` annotation causes perpetual OutOfSync diffs with `ServerSideApply=true`. Fix: `ignoreDifferences` with `jsonPointers: [/metadata/annotations]` scoped to the specific resource with `name:` and `kind:`. `jqPathExpressions` does not work for this case in ArgoCD v2.12 — the `jsonPointers` form scoped by name should be the default pattern for any DaemonSet annotation drift.

7. **Operator webhook `failurePolicy` drift.** Operators (Istio, others) that dynamically patch `failurePolicy` on ValidatingWebhookConfigurations at runtime will always cause ArgoCD drift. Add `ignoreDifferences` with `jsonPointers` for `/webhooks/0/failurePolicy`.

## Rendering caveats

8. **ArgoCD does NOT pass `--kube-version` to `helm template`.** `.Capabilities.KubeVersion.GitVersion` is empty in ArgoCD rendering, so charts that auto-detect platform (e.g. checking for the `-gke` suffix) silently fail. Always set platform-specific values explicitly in provider files rather than relying on capability detection.

## Namespace & sync options

9. **Create namespaces in the chart, not via `CreateNamespace=true`.** Platform/infra charts (policy engines, runtime security agents, cert managers, service meshes, gateway controllers, progressive-delivery controllers) must include a `templates/namespace.yaml` that renders the Namespace. This makes the namespace declarative, version-controlled (labels/annotations), and cleanly pruned on app deletion. Only legacy/simple services may still use `CreateNamespace=true`. New charts must always follow the chart-managed pattern.

10. **`ApplyOutOfSyncOnly=true` reduces noise and apply churn** on large applications. Most repos should set it. Don't combine with aggressive self-heal on stateful workloads.

11. **`ServerSideApply=true` is required for any chart that installs CRDs.** CRDs are large and routinely exceed the 262KB `metadata.annotations/last-applied-configuration` limit with client-side apply. Charts without CRDs do not need it.

12. **`CreateNamespace=true` conflicts with charts that include a Namespace template.** Before adding to `syncOptions`, check:
    ```bash
    grep -r "kind: Namespace" charts/<chart-name>/templates/
    ```
    If found, omit `CreateNamespace=true`.

## Tag-based rollouts

13. **For tag-based rollouts**, never use commit SHAs as `targetRevision` in production. Use named tags (e.g. `stable-v1.2.3`) plus a mutable promotion tag. ArgoCD tag-based sync is eventually consistent — recheck after 2–5 minutes before troubleshooting.
