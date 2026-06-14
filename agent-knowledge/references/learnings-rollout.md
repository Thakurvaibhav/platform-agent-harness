# Rollout Learnings

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
