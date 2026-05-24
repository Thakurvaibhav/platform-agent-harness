# ArgoCD Learnings

Numbered, append-only. **Update the existing entry — never duplicate.**

1. **`ignoreDifferences` requires `RespectIgnoreDifferences=true` in `syncOptions`.** Without this option, ArgoCD still overwrites the live value during sync even though the diff is hidden in the UI. Symptom: live values keep resetting after each sync.

2. **Sync-waves on Application objects only enforce ordering during app-of-apps sync.** They do NOT control when Applications sync their own contents. For guaranteed ordering between independent child Application syncs, use a multi-PR phased approach.

3. **Values key naming must be lowercase kebab-case** when keys become Helm release names downstream. Avoid camelCase. Use `index .Values "key-name"` for hyphenated keys in templates.

4. **`CreateNamespace=true` conflicts with charts that include a Namespace template.** Before adding to `syncOptions`, check:
   ```bash
   grep -r "kind: Namespace" charts/<chart-name>/templates/
   ```
   If found, omit `CreateNamespace=true`.

5. **`ApplyOutOfSyncOnly=true` reduces noise and apply churn** on large applications. Most repos should set it. Don't combine with aggressive self-heal on stateful workloads.

6. **CRDs need `ServerSideApply=true`** to avoid `metadata.annotations.last-applied-configuration` bloat (CRDs often exceed the 256 KiB annotation limit otherwise).

7. **For tag-based rollouts**, never use commit SHAs as `targetRevision` in production. Use named tags (e.g. `stable-v1.2.3`) plus a mutable promotion tag. ArgoCD tag-based sync is eventually consistent — recheck after 2–5 minutes.

8. **Sync wave gotcha:** sync waves on `Application` resources (in app-of-apps) order *Application creation*, not sub-application *content sync*. To order content sync, split into multiple PRs and merge them in sequence.
