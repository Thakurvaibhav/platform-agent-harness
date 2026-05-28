# Kubernetes ServiceAccount & Identity Learnings

Read this file when working on ServiceAccount separation, cloud Workload Identity (GKE WI, EKS IRSA, AKS WI), image-pull secrets, or cloud-IAM bindings.

Numbered, append-only. **Update the existing entry — never duplicate.**

## SA separation patterns

1. **Per-service SAs should inherit cloud IAM from a global default, not per-service config.** When all services in a namespace share the same cloud IAM role, set `global.serviceAccount.annotations` at the umbrella / host-cluster level. Individual charts merge global + per-service annotations via the `merge` Helm helper. This avoids duplicating the same IAM annotation across N charts and makes per-service overrides (a service that needs its own dedicated cloud SA) a simple values addition.

2. **AWS-style image-pull secrets are needed on EKS — GCP/Workload-Identity is not.** On EKS, the shared SA typically carries `imagePullSecrets: [{name: <pull-secret>}]` for private-registry access. New per-service SAs on EKS must replicate this or pods fail to pull images. GCP clusters using Workload Identity for registry auth don't need `imagePullSecrets`. Model this as a per-cluster setting (`global.serviceAccount.imagePullSecrets`) alongside the cloud IAM annotations.

3. **PR-preview deployments must not create SAs.** When a chart adds `serviceAccount.create` support, PR-preview values must explicitly set `create: false`. Previews deploy into the same namespace as the dev app — creating a duplicate SA causes conflicts or overwrites the dev SA's annotations.

4. **Namespace-level `principalSet://` bindings replace per-SA WI bindings at scale.** GKE Workload Identity normally requires a per-SA IAM binding (`serviceAccount:<project>.svc.id.goog[<ns>/<sa>]`). With many services getting dedicated SAs, this doesn't scale. Use:
   ```
   principalSet://iam.googleapis.com/projects/<project-num>/locations/global/workloadIdentityPools/<project-id>.svc.id.goog/namespace/<namespace>
   ```
   to cover all SAs in a namespace with one binding.

5. **Services with dedicated cloud SAs need per-SA WI bindings — namespace-level `principalSet` is unsafe for them.** Any service with a dedicated cloud SA (e.g. a service that needs database admin permissions distinct from the shared role) cannot rely on the namespace-level binding — that would grant every SA in the namespace those elevated permissions. When renaming such a K8s SA, an explicit per-SA WI binding must be added in Terraform for the new name.

6. **Batch SA template rollout is safe when `create: false` is the default.** Adding `templates/serviceaccount.yaml` to many charts in a single PR is a no-op change — no SA is created until `create: true` is explicitly set per component per cluster. Pilot one service end-to-end first, then batch the template addition.

7. **Production SA renames need a Terraform-first sequence.** When renaming an SA that has a dedicated cloud binding, apply the new IAM binding (Terraform) BEFORE enabling the new K8s SA. Make the IAM binding additive (do not replace the old binding) so the previous SA keeps working during the transition.

## Validation operations

8. **Enumerate every host-cluster file explicitly in batch dispatch prompts.** Sub-agents will silently skip clusters they weren't told about. List all N host-cluster files by full path, then verify:
   ```bash
   git diff --name-only origin/main | grep host-clusters | sort
   ```
   shows exactly N lines before pushing.

9. **Local `helm template` for prod overlays may require stacking multiple values files.** If the chart layers `environments/<env>.yaml` and `host-clusters/<cluster>.yaml`, both must be passed when rendering locally — otherwise template errors are misleading. Mirror the ArgoCD app's full values-file list when validating locally.

10. **Tag-pinned clusters defer all changes until the tag is bumped.** When ArgoCD `targetRevision` is pinned to a specific chart version, changes merged to `main` are invisible on-cluster. Validation status for pinned clusters should be recorded as **DEFERRED**, not **FAILED**.

11. **Disabled services (`enabled: false`) are NO_DEPLOY — skip in validation.** Many services are enabled on only a subset of clusters. A "missing" SA on a cluster where the service is disabled is expected, not a regression.

12. **Per-service SA validation is a 4-step check.** (1) SA exists with the correct cloud IAM annotation. (2) Deployment `serviceAccountName` matches and all replicas Ready. (3) Pod health — all Running, 0 restarts, no old-ReplicaSet stragglers. (4) Logs spot-check for IAM auth regressions.

13. **Bundle-enablement matrix determines actual blast radius.** A host-cluster values-file edit is a no-op if that cluster doesn't have the corresponding ArgoCD Application (bundle) enabled. Check the matrix before dispatching.
