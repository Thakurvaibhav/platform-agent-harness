# ArgoCD Learnings

See also: `learnings-helm-ci.md`, `learnings-progressive-delivery.md`, `learnings-operators.md`, `learnings-crossplane.md`, `learnings-terraform.md`

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

## Drift & ignoreDifferences (continued)

14. **Setting only `ServerSideApply=true` (without also setting `ServerSideDiff=true`) engages server-side-apply for the actual sync, but diffs still use client-side diff logic — the two syncOptions are independent, not a package deal.** That means: syncs use the SSA field manager for apply (so you get past the ~262KB last-applied-configuration annotation limit that breaks client-side apply on large objects like CRDs), but the drift/diff view keeps computing differences the old client-side way rather than switching to full SSA-diff semantics (which would show every server-owned field as a diff and over-report). This is usually the combination you want: SSA apply where you need it (large or CRD-installing resources) without SSA diff turning on cluster-wide over-reporting. (argoproj/argo-cd#22151.)


## Health status & sync-wave gating

15. **ArgoCD's own `Application`-of-`Application`s health customization was removed upstream, and its absence has a silent failure mode that a green-looking parent app can hide entirely.** Two facts compound: (1) Application health assessment was removed upstream (Argo CD v1.8, argoproj/argo-cd#3781) and there is no shipped `health.lua` for it anywhere in argo-cd's own resource-customization tree — the only surviving trace is a documentation snippet under the operator manual's health-assessment page, in the *flattened* `argocd-cm` key form; a Terraform- or Helm-managed `resource.customizations` block using the *nested* map form must transpose that snippet, not paste it verbatim. Without ANY override, a child `Application`'s health is `nil` and every non-hook sync task auto-succeeds — sync waves never actually gate on child health at all, silently defeating the entire reason for using sync waves in an app-of-apps layout. Verified at Argo CD v3.3.6 / gitops-engine `sync_context.go:477-492` + `sync_tasks.go:274-276`: with the override correctly in place, a `Progressing` child BLOCKS wave progression and a `Degraded` child FAILS the whole app-of-apps sync — but (2) the parent's own health ROLLUP ignores `Unknown` children when aggregating (`controller/health.go:73-75`), and any child whose own `status.health.status` is empty, missing, or not a recognized enum value becomes `Unknown`. The net effect: a wave can stall forever on an `Unknown` child while the PARENT still reports fully `Healthy` — nothing goes `Degraded`, nothing pages, nothing looks wrong from the top. When adding or debugging this customization, assert that every child health script only ever emits a recognized enum value, and treat "a wave that never advances, with a green parent" as this exact signature.


## Sync policy & autosync semantics

16. **Checking `.spec.syncPolicy.automated != null` to detect whether auto-sync is enabled is wrong — the block EXISTS on a disabled app too.** A disabled application carries `{"enabled": false, "prune": true, "selfHeal": true}` rather than an absent block, so a presence check reports `true` (auto-sync enabled) when it is actually off; `== true` on the whole object is equally wrong for the same reason. The correct predicate checks the `enabled` sub-field specifically against `false`: `.spec.syncPolicy.automated.enabled != false`. This is the same "presence read as OK" bug shape that shows up anywhere a nested optional block can exist-but-be-disabled rather than exist-or-not; it produces confidently wrong diagnoses in ad-hoc tooling, not just in formal checks.


## Drift & ignoreDifferences

17. **Duplicate entries in an associative-list field (a list field keyed by a merge-key like `name`, e.g. container `env`, `volumes`) are accepted by Kubernetes API validation but dangerous under Server-Side Apply — and the resulting error names the wrong thing.** Any field carrying a Kubernetes list-map merge-key annotation has no uniqueness check in the API server's own validation, so a manifest with two same-keyed items in that list applies fine under plain client-side apply. Under Server-Side Apply, the structural merge treats duplicate-keyed entries as ONE logical item and merges their fields together — which can set mutually-exclusive fields on the same merged item and fail with an error message that looks completely unrelated to duplication (e.g. a "may not be specified together" error on two fields that were never meant to coexist). This can also differ from how a DOWNSTREAM consumer resolves the same list (e.g. a process reading env vars via a last-write-wins map), so reading only one layer's source code can look authoritative while a different, earlier layer (the apiserver's own SSA merge) actually gates the behavior first. Whenever the question is "does my new value override the built-in one," resolve it against the ACTUAL apply path in use (client-side vs Server-Side Apply) and confirm empirically with a read-only diff against the live object, not by reading source alone.


## Pruning semantics

18. **Pruning a `CronJob` through GitOps CASCADE-DELETES its spawned `Job`s and their pods — the standard claim "in-flight Jobs are unaffected and will finish" is false for any CronJob removal.** Jobs spawned by a CronJob carry an owner reference to it with `blockOwnerDeletion: true`, so deleting the parent takes every Job it owns with it — including manually-triggered ones that still carry the CronJob as an owner even without a controller-managed label. Retained Jobs kept around by a job-history limit are garbage-collected the same way and are not separately tracked by the GitOps tool as "its" resources. Before writing a claim like "removing this CronJob is safe, in-flight runs will complete," verify the actual owner references on any running Jobs with a direct read (`kubectl get jobs -o json` and inspect `ownerReferences`) — don't assume Kubernetes ownership semantics match the intuitive claim.


## Sync policy & autosync semantics

19. **`automated.enabled: false` wins over `selfHeal`/`allowEmpty` unconditionally — adding those flags to an application whose sync policy already carries `enabled: false` is completely inert.** At Argo CD v3.3.6, the sync-policy predicate that gates automated sync (`SyncPolicy.IsAutomatedSyncEnabled`, `pkg/apis/application/v1alpha1/types.go:1488-1493`) returns false whenever `automated.enabled` is explicitly false, and never consults `selfHeal` or `allowEmpty` at all — so an app in that state will not self-heal no matter what else is set on the same policy block. If the disabling was applied out-of-band (manually, not through the GitOps source), it also cannot necessarily be fixed by re-applying the desired config through your normal IaC path if that path never explicitly sets `enabled` itself — check whether your provisioning code emits the `enabled` key at all, or whether it's silently relying on the default.

20. **`ignoreDifferences` combined with `ApplyOutOfSyncOnly=true` can report an application fully `Synced` while a changed desired value NEVER actually lands.** If a field is covered by `ignoreDifferences`, a git-side change to that field produces no visible diff, so the app shows `Synced`; with `ApplyOutOfSyncOnly` enabled, a resource showing no diff is never re-applied at all — so the new desired value silently never reaches the live object, even though git and the sync status both look correct. Concretely: a chart change that lowers a workload's replica count can leave the live replica count completely unchanged while the app reports `Synced`. Fixes, in order of preference: remove the now-obsolete `ignoreDifferences` entry so the real diff surfaces again; make a one-time manual change to match the new desired value (it then "sticks" because git and live agree); or wait for an unrelated full apply (e.g. an image bump) to happen to also carry the field through. Whenever a chart change makes an existing `ignoreDifferences` entry obsolete, remove the entry in the SAME change, not as a follow-up.


## Drift & ignoreDifferences

21. **Under `ServerSideApply=true`, a SPECIFIC-KEY `ignoreDifferences` jsonPointer does not suppress a controller-injected annotation — only the WHOLE-BLOCK form does.** A per-key pointer targeting one specific annotation key fails to clear an out-of-sync status when a different controller injects that exact annotation at runtime and the app uses Server-Side Apply — even combined with `RespectIgnoreDifferences=true` and a hard refresh. The whole-block form (pointing at the entire `/metadata/annotations` subtree on the affected resource kind) does work. Root cause: the desired manifest renders an empty annotations block while live carries the injected key, and under SSA the per-key normalization doesn't clear a key that desired never declared at all, while the whole-subtree ignore does. This is the SSA-specific counterpart to the same whole-block pattern needed for injected annotations under plain client-side apply — the reason (a controller injecting a key the chart never declares) is the same, but the mechanism that fails to suppress it differs by apply mode. Always verify an `ignoreDifferences` fix against the LIVE application (patch it, hard-refresh, confirm it goes fully synced) before claiming it works — a correctly-rendered `ignoreDifferences` entry is not proof it actually suppresses the diff under your apply mode.

---
