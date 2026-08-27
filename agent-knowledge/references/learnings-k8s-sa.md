# Kubernetes ServiceAccount & Identity Learnings

Read this file when working on ServiceAccount separation, cloud Workload Identity (GKE WI, EKS IRSA, AKS WI), image-pull secrets, or cloud-IAM bindings.

See also: `learnings-crossplane.md`, `learnings-workload-debug.md`

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

14. **Resolve an EKS cluster's IRSA OIDC provider ARN even when `iam:ListOpenIDConnectProviders` is DENIED** (a scoped SSO role often lacks it): (1) get the issuer — `aws eks describe-cluster --name <cluster> --query cluster.identity.oidc.issuer`, strip `https://` → issuer host; (2) the provider ARN is deterministically `arn:aws:iam::<acct>:oidc-provider/<issuer-host>`; (3) CONFIRM authoritatively by reading an existing IRSA role's trust policy — `aws iam get-role --role-name <role> --query Role.AssumeRolePolicyDocument.Statement[].Principal.Federated` (its `StringEquals` condition keys give `<issuer-host>:sub` / `:aud`). Useful for filling an OIDC block (e.g. a Crossplane `EnvironmentConfig`) without the list permission.

## Cloud IAM / Terraform verification

15. **`terraform plan` does not validate IAM role strings against the cloud provider's API.** A `google_project_iam_member` (or equivalent AWS/Azure resource) referencing a misspelled or nonexistent role name passes `terraform plan` cleanly and only fails at `apply` time, because `plan` treats the role name as an opaque string it never checks against a live API. Before trusting a green plan as proof a role reference is correct, verify predefined roles independently — e.g. `gcloud iam roles describe <role>` — especially for roles with easily-confused, near-identical names.

16. **GCP Memorystore for Valkey IAM authentication requires `roles/memorystore.dbConnectionUser`, granting `memorystore.instances.connect` — a permission named `memorystore.instances.connectWithIamAuth` does not exist despite being the obvious-looking match.** Confirmed against the live IAM roles API (`gcloud iam roles describe roles/memorystore.dbConnectionUser`), not from documentation alone. Do not confuse this with the separate Redis Cluster role `roles/memorystore.redisClusterConnectionUser` — same product family, different role, different granted permission.
    - If binding this via a GKE cluster's Workload-Identity default GCP service account, project-scoped binding is intentionally broad when other instances in the project use a different auth mode — the grant is only effective for instances actually configured for IAM auth.

17. **Memorystore for Valkey IAM_AUTH without TLS sends the OAuth bearer token over the wire in plaintext, and the field that fixes it is immutable after creation.** GCP's own documentation states the AUTH command (carrying the IAM token) is unencrypted unless in-transit encryption is enabled. `transit_encryption_mode` is set at creation time only — changing it later requires destroy/recreate, and the commonly-used Terraform module for this resource (`terraform-google-modules/memorystore/google//modules/valkey`, `~> 15.2`) defaults it to disabled. Any instance using IAM authentication should set `transit_encryption_mode` to the server-authentication value explicitly at creation time — the empty-instance window before applications connect is the only low-cost moment to make this choice.

18. **General pattern for changing an immutable field inside a Terraform `for_each` map without replacing every sibling resource: pin the default to the CURRENT live value, then override only the single entry you actually want to change.** A defaults-plus-per-entry-override map (e.g. an `instance_defaults` block merged with per-entry `instances`) that sets the new value directly as the default force-replaces every existing resource in the map, because the module then compares every entry against a value that differs from what is actually live. Instead: (1) set the default to match what is already live — this produces zero diff on existing resources; (2) override only the target entry to the new value; (3) wire the field through as `each.value.<field>` rather than a shared default. Verify via `terraform plan`: the target entry should show as a genuine replacement while every sibling shows only a refresh with zero changes.


## SA separation patterns (continued)

19. **A Helm "merge global + local annotations" ServiceAccount template with fill-in (last-write-wins-only-if-unset) semantics gives a component no way to opt OUT of a bundle-wide annotation.** If the template is `merge $localAnnotations $globalAnnotations` (Sprig `merge`: first-source-wins per key, but fills in anything absent from the first map), a component setting `annotations: {}` (or `""` / `null`) is indistinguishable from not setting the key at all — the global value always fills in. An `identity.source`-style enum of two states (e.g. managed/unmanaged) doesn't add a real "none" state either.
    - **Fix idiom:** guard with `hasKey` plus a length check and render nothing in that branch. Use `if`/`else`, not a ternary (Go templates evaluate both branches of a ternary expression), and merge into a freshly-allocated dict — `merge` mutates its first argument in place, and pointing that first argument at `.Values` corrupts the source data.
    - **Don't generalize across resource kinds** — a CronJob's ServiceAccount template is often local-only with no global merge at all, so a finding on a Deployment's SA template doesn't automatically apply to a CronJob's.


## GKE Workload Identity credential caching

20. **On GKE Workload Identity, `google-auth`'s Python client library self-pins to a resolved GSA email on first token refresh — the pin lives inside the library, not application code, so whether a client survives a bound-identity change is decided by which auth library it uses, not by anything grep-able in its own source.** Traced in `google-auth` (confirmed stable across three recent minor releases): `google.auth.default()` constructs `compute_engine.Credentials()` with no `service_account_email`, defaulting to the safe `"default"` alias. The first `refresh()` call resolves account info and then **rebinds** the credentials object's stored email to the concrete resolved address — from that point on, every subsequent refresh hits the email-specific metadata path instead of the safe alias. When the underlying KSA's bound GSA changes, that email-specific path 404s forever, eventually raising a transport/refresh error. A repo-wide grep for `service_account_email` in application code finds nothing, because the pin happens entirely inside the library at runtime. For contrast: some other Python metadata-client libraries hardcode the `default` alias path and never pin, and are genuinely immune. For any Python service using this class of library, decide "will this break on the next identity change" from which auth library it uses, not from its own code.
    - **A parallel, harder-to-see variant hits signed-URL / signBlob paths.** A Java/Scala-ecosystem auth library's compute-engine credentials class caches the resolved account email for process lifetime the same way, then passes it as an explicit **API parameter** to a blob-signing call rather than a URL path. Because the *token* is still fetched via the safe default alias, the client stays healthy-looking and emits no email-specific metadata request at all — it fails silently, signing as the OLD principal (impersonation) until that principal is revoked, visible only in the cloud IAM-credentials service's own signing audit logs, never in the metadata-server audit trail used to detect the first variant. Detection requires a dedicated audit-log query for the signing API, comparing the resolved target principal against the actual caller, resolved by a stable numeric identity rather than email (emails get renamed/reused).

21. **A silent identity-cutover break can leave a fully healthy-looking pod and zero IAM denials — the three signals people reach for each give a confident false negative.** When a client's stale-cached-credential path fails, the failure mode is typically an unavailable/timeout error on the *data* call, not a permission denial. Consequence: (1) pod logs are a false negative once the failure is more than a log-rotation window old — check centralized/cloud logging, not the live pod's own log tail; (2) a `PERMISSION_DENIED`-style audit-log query returns clean by design, because a vanished credential path yields "unavailable/unresolvable", never an authorization error, so a clean denial query is not evidence of a healthy cutover; (3) a backlog/queue-depth minimum-over-window metric is not proof of a live consumer — the minimum observed can be a stale pre-failure value rather than evidence of current throughput. The reliable discriminators are activity-rate metrics for the specific dependency (an ack/throughput rate rather than a backlog minimum) and confirming there is no code path at all in this failure class that would produce a denial — absence of denial errors is exactly what this failure looks like when supposedly healthy.


## SA separation patterns

22. **Whether `imagePullSecrets` is needed is a property of the cloud provider, and cluster names are not reliable evidence of provider — verify from the actual provider configuration, never infer from naming.** EKS clusters typically need an explicit `imagePullSecrets` entry for private-registry pulls; GKE clusters using Workload Identity typically don't. A cluster can be historically mislabeled in tooling or reference tables — named as if it were one provider, later migrated, or simply never accurately classified. Confirm the provider from the per-cluster values file's actual cloud include, or from a rendered ServiceAccount's IAM-annotation shape (a Workload-Identity-style annotation key versus an IRSA-style one) — never from the cluster's own name or a table that could be stale.
