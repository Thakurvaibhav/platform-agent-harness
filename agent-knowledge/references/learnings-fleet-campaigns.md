# Fleet Campaign Learnings

See also: `learnings-agent-workflow.md`

Numbered, append-only. **Update the existing entry — never duplicate.**

## Strategy

1. **Phase by blast radius, not by chronology.** Dev → stag → prod is the canonical pattern, but the smaller cut inside each phase is per-cluster or per-namespace, not "all at once after a delay".

2. **Soak between phases matters more than soak duration choice.** Even a 24-hour soak in the previous environment catches the majority of issues that would otherwise surface in the next. Don't promote without a soak.

3. **First PR establishes the pattern, then delegate.** Do the first cluster/instance manually to create a concrete reference. Subsequent delegations can reference it with decreasing prompt size — by the last cluster, a one-line prompt suffices. The first manual PR is not wasted effort; it is the reference that makes all subsequent delegations reliable.

4. **Environment replication cost approaches zero once the pattern is established.** The first environment (dev) takes full effort to establish the pattern. The second (stag/test) takes ~50% because the agent handles variant differences (namespace, SA, cloud provider). By the third (prod), marginal cost per additional cluster is near-zero — the agent produces correct PRs from a single-line dispatch.

5. **Staged rollout for CRD field migrations.** Use a 1-file canary (single service) then batch the remainder. Validates the new field path works before wide blast radius. (Example: migrating an operator's `resyncInterval` from a top-level key to a nested `syncConfig.resyncInterval` should be 1 canary PR, then a batch PR for the rest.)

## Enablement & guardrails

6. **4-file enablement checklist per cluster.** When enabling a tool on a new cluster, touch: (a) argo-apps values, (b) environment defaults, (c) host-cluster overrides, (d) the guard policy if applicable. Missing any one produces a partial enablement that looks healthy but doesn't enforce.

7. **Guard policy pattern (policy engines).** Pair every CRD-based component with a ValidatingPolicy that prevents unsafe configurations. Deploy as **Audit → soak → Deny** — never go straight to Deny. Common examples: a "require monitor mode" policy on runtime security agents that prevents accidental enforcement; NetworkPolicy and AuthorizationPolicy guards.

8. **Confirm ownership before enabling on shared environments.** Enablement on test/prod may be owned by another team (e.g. policy content owned by infosec). Always confirm before acting. A rollout has been reverted before because the policies were owned by a team that wasn't consulted.

## Mutation & rebuilds

9. **Operator upgrades that touch CRDs need their own PR.** Bundling chart upgrade + values change + enablement in one PR makes rollback ambiguous. Separate: (a) chart bump, (b) per-cluster enablement.

10. **Immutable-field changes require delete-and-recreate.** Includes `StatefulSet.spec.volumeClaimTemplates`, `Service.spec.clusterIP`, `Job` template fields, certain `Deployment` selectors. Plan the recreation in the PR description and verify CR ordering.

## Validation & metrics

11. **Verify metric names and namespaces against live endpoints before dashboards.** Never assume metric names or namespaces. Run `curl <metrics-endpoint>` on a live pod to confirm before writing PromQL or Grafana panels. Skipping this verification routinely produces follow-up fix PRs.

12. **Automated soak analysis via Grafana MCP replaces manual dashboard inspection.** Instead of manually staring at dashboards for 14 days, query Prometheus programmatically over 7-day windows using Grafana MCP. The agent can query specific metrics, separate signal from noise (e.g. mesh-internal vs egress failures), cross-reference with pod health, and produce a definitive PASS/FAIL verdict. Cuts ~4–6h of manual inspection per cluster to ~10min of agent time.

## Release gating

13. **Production tag mutation needs `--force-with-lease`.** Direct `git push --force` to a stable tag is denylist territory. Use named tags + a moving promotion tag.

14. **Versioned tag strategy for production canary.** Use `<tool>-v0.X` tags for canary clusters before updating the `<tool>-stable` tag. Gives fine-grained rollout control without code changes. After canary validation, force-update the stable tag and consolidate canary clusters back to stable in one PR.

15. **Two-step tag release for production.** Create an immutable versioned tag first (`<tool>-v0.1.13`), then promote to production by pointing the mutable stable tag at it (`git tag -f <tool>-stable <tool>-v0.1.13`). This gives: (a) audit trail of what version is running, (b) instant rollback by re-pointing stable to a previous versioned tag, (c) no code changes needed for rollback.

16. **Tag-based GitOps sync is eventually consistent.** After moving a stable tag, expect 2–5 minutes before ArgoCD reconciles. Don't troubleshoot before re-checking.

## Log volume

17. **Log-volume filtering during rollouts is mandatory.** Enabling a tool with a chatty default on N clusters can 10x log spend overnight. Configure log filtering in the same PR that flips the enable flag. For eBPF-based tools, the volume can be extreme (multiple MB/s per cluster) — filter health checks, infrastructure namespaces, and known-safe agent binaries. Always validate the deny list renders correctly with `helm template`; wrong nesting depth silently falls back to no filtering.

## Cross-repo coordination

18. **Cross-repo rollouts are coordinated through bd dependencies, not chat.** When a chart in repo A depends on a CRD shipped from repo B, model the dependency in bd as `blocks` so the orchestrator can't start the dependent work too early.

19. **Infrastructure changes spanning multiple repos need sequenced PRs.** When a Kubernetes change (new ServiceAccount) depends on a Terraform change (IAM binding), sequence matters. Create the IAM binding first (Terraform repo), then enable SA creation (K8s repo). For rollback safety, the IAM binding should be additive (not replacing existing bindings) so the previous SA keeps working during the transition.

## Batch campaign hygiene

20. **Pilot-then-batch for wide-blast-radius changes.** For changes touching 50+ charts, pilot with 1 service end-to-end (template + enablement + validation across all clusters), fix all issues discovered, then batch the template addition to all charts as a no-op PR. The pilot surfaces 100% of the integration issues; the batch PR is mechanical.

21. **Conservative batch sizing for prod.** Dev/test can use 5-service batches. Prod should use 4 (or smaller) to limit blast radius per PR. The marginal time cost is minimal (~2 extra dispatches) because the pattern is mechanical, but the risk reduction per merge is meaningful in production.

22. **Post-batch inventory audit is mandatory after each prod campaign.** Compare the full prod service inventory against all batch manifests. Real campaigns regularly miss 1–3 services despite complete dev/test coverage. Build the audit step into the dispatch workflow: (1) plan batches, (2) execute batches, (3) audit for gaps, (4) gap-fill.

23. **Gap-fill PRs are normal — plan for them.** In large batch campaigns (50+ services, 15+ PRs), expect 1–3 services to be missed from batch manifests. Causes: services added after batch planning, naming differences between environments, services in bundles not covered by the main batch scope. Detecting gaps via systematic audit is cheaper than exhaustive upfront planning.

24. **Catch-up PRs for missed clusters should be single large PRs.** When a cluster is discovered missing from multiple batches, fix all affected services in one catch-up PR rather than retroactively amending each batch. Faster to review, easier to track, and reduces merge-queue congestion.

## Bundle/release pipeline gaps

25. **A CI/CD pipeline that only validates against test-tier clusters is structurally blind to any failure caused by config that exists in prod but not in test.** If a pipeline gates promotion on tests passing against non-prod environments, and prod carries additional configuration (an env var, a feature flag, a secret) that test environments don't have, no amount of green test runs can catch a failure caused by that config's absence or presence. Fix is either: make test environments mirror prod's configuration surface, or have the pipeline run a read-only health check directly against prod after deploy rather than relying solely on pre-deploy test-tier validation.

26. **A new hard-fail startup validation (e.g. exiting the process when a required config value is missing) turns a pre-existing misconfiguration into an outage the moment it ships — even though the misconfiguration was already there and harmless.** The validation is correct in principle but instantaneous in effect: any environment already missing that config goes from "quietly wrong" to "down" on deploy, with no warning period. Safer rollout pattern: ship the check as a logged warning (or a metric) first, confirm every environment is clean over a bake period, and only then promote it to a hard failure in a later release.

27. **When application code and its infrastructure configuration live in separate repositories, a new startup requirement added on the application side and the config it depends on being added on the infra side can both look correct in isolation and still combine into an outage, because neither review saw the other change.** There's no single reviewer with visibility into the combination. A PR that adds a new hard requirement for a piece of config should either ship that config for every environment in the same change, or tolerate the config's absence gracefully until every environment is confirmed to have it — don't assume a companion change elsewhere has already landed everywhere.

28. **When a GitOps target pins a specific release tag rather than tracking a branch directly, a config change that lands and passes validation on the tracked branch can sit invisible for days before it reaches that pinned target — and "it's been fine on main" proves nothing about the pinned environment until the tag actually moves.** The gap between "validated on the branch" and "live on the pinned target" is exactly the same size as the release cadence for that target, and during that whole window a change that looks fully validated is simply not running there yet. Any environment pinned to a release tag needs its own confirmation once that tag is bumped, regardless of how long the change has soaked on the branch.

29. **A rolling-update strategy that keeps old, healthy pods serving while new pods crash-loop means no outage alert fires and the top-level deployment health stays green — a broken new revision can go unnoticed for days.** As long as the previous ReplicaSet still has available replicas, the Deployment (and anything that summarizes health from it, like a GitOps reconciler's own health check) reports healthy, because from that layer's point of view traffic is being served. The failure is invisible unless something specifically watches for restart counts or CrashLoopBackOff pods rather than aggregate replica availability. Alert on container restart rate or crash-looping pod count per workload, independent of whether the Deployment as a whole still looks Ready.

30. **A deploy pipeline that only health-checks BEFORE releasing only ever proves the old state was fine — add a post-deploy check with a short bake window, or any failure that only manifests after the new config takes effect (a mismatch, a new validation, a missing secret) ships completely silently.** A pre-release check and a post-release check are answering different questions; a pipeline that only asks the first one has no way to catch a regression that the release itself introduces.


## Batch campaign hygiene (continued)

31. **For a multi-target phased rollout with repeated validation runs, keep exactly one (or two, if you separate a broad pass from a deep pass) append-only report file per target rather than a new file per run.** Repeated validation runs append a dated section to the existing file instead of creating rerun-suffixed, dated, or per-dimension files — this keeps a target's full validation history in one place instead of scattered across files that are easy to miss on the next pass. If multiple parallel workers validate against the same consolidated file, don't have each one append directly (concurrent writers race and corrupt the file) — have each return its verdict through whatever result-passing mechanism you use, and have one place author the single dated section afterward.
