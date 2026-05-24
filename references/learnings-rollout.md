# Rollout Learnings

Numbered, append-only. **Update the existing entry — never duplicate.**

1. **Phase by blast radius, not by chronology.** Dev → stag → prod is the canonical pattern, but the smaller cut inside each phase is per-cluster or per-namespace, not "all at once after a delay".

2. **Soak between phases matters more than soak duration choice.** Even a 24-hour soak in the previous environment catches the majority of issues that would otherwise surface in the next. Don't promote without a soak.

3. **Operator upgrades that touch CRDs need their own PR.** Bundling chart upgrade + values change + enablement in one PR makes rollback ambiguous. Separate: (a) chart bump, (b) per-cluster enablement.

4. **Immutable-field changes require delete-and-recreate.** Includes `StatefulSet.spec.volumeClaimTemplates`, `Service.spec.clusterIP`, `Job` template fields, certain `Deployment` selectors. Plan the recreation in the PR description and verify CR ordering.

5. **Production tag mutation needs `--force-with-lease`.** Direct `git push --force` to a stable tag is denylist territory. Use named tags + a moving promotion tag.

6. **Cross-repo rollouts are coordinated through bd dependencies, not chat.** When a chart in repo A depends on a CRD shipped from repo B, model the dependency in bd as `blocks` so the orchestrator can't start the dependent work too early.

7. **Batch campaigns (e.g. enabling N services on a new feature) need a gap-fill audit.** After the campaign, run a single read-only sweep checking every service is on the expected version — campaigns drift more than people expect.

8. **Log-volume filtering during rollouts is mandatory.** Enabling a tool with a chatty default on N clusters can 10x log spend overnight. Configure log filtering in the same PR that flips the enable flag.

9. **Tag-based GitOps sync is eventually consistent.** After moving a stable tag, expect 2–5 minutes before ArgoCD reconciles. Don't troubleshoot before re-checking.
