# Operators, CRDs & Policy Engine Learnings

Numbered, append-only. **Update the existing entry — never duplicate.**

## Operators & CRDs

1. **eBPF-based kprobes must be validated against all target kernel versions.** Kernel function names change across versions; mixed node pools can have different kernels. Before adding kprobes, check `/proc/kallsyms` on nodes of each kernel version in the target cluster. Applies to runtime security tools that hook kernel functions.

2. **ServiceMonitor `jobLabel` takes a label key, not a value.** `jobLabel: app` means "use the value of the `app` label on the Service as the `job` label in Prometheus." The Service must have that label set, or the resulting `job` is empty.

3. **Transient operator errors may self-heal.** External-API timeouts on operator reconciliation (e.g. a secrets operator hitting `i/o timeout` against its backend) can show CRs as unhealthy. Recheck after 5 minutes before escalating — most self-heal on the next reconciliation cycle.

## Policy engine patterns (Kyverno-style)

Policy engines deployed cluster-wide are a core platform capability. When onboarding new tools or infrastructure, proactively consider whether policies can enforce safety invariants, gate rollouts, or provide audit visibility. Three common patterns:

- **Guard policies** — prevent unsafe config (e.g. require runtime security agents to start in monitor mode, not enforce).
- **Mutation-assisted rollouts** — inject labels/annotations at admission (e.g. service mesh enrollment, sidecar injection).
- **Audit policies** — track compliance via a policy reporter (e.g. missing probes, missing resource requests).

4. **ValidatingPolicy requires `evaluation.background.enabled: true` to score existing resources.** By default, ValidatingPolicy only evaluates on admission (CREATE/UPDATE). Without background scanning enabled, the Policy Reporter UI shows no results for resources created before the policy was deployed.

5. **Policy Reporter `uncontrolledOnly` must be `false` to see pod reports.** By default, Policy Reporter filters to "uncontrolled" resources (not owned by a ReplicaSet/Deployment). This hides nearly all pod-level policy results since most pods are Deployment-managed. Set `uncontrolledOnly: false` in `sourceFilters`. Also add `KyvernoValidatingPolicy` to `sourceFilters.selector.sources` to include the CEL-based policy type, and enable `periodicSync` for timely report refresh.

6. **MutatingPolicy for zero-disruption rollouts.** When onboarding infrastructure that requires pod-level labels or annotations (service mesh enrollment, sidecar injection, runtime-security namespace labels), use a MutatingPolicy to inject at admission rather than hot-labeling running pods. This piggybacks on natural CI/CD rollout cadence and avoids disrupting existing workloads. Pair with a ValidatingPolicy (audit + background) to track progress in the policy reporter.

7. **Admission controller must be restarted after new CRDs are installed.** When a ValidatingPolicy watches a CRD-based resource (e.g. a custom resource provided by another operator) and the policy is deployed before the CRD exists, the admission controller caches resource discovery at startup. It will actively deny CREATE/UPDATE with `resource <name> not found in group <group>/<version>` — even with `failurePolicy: Ignore` (because the webhook is denying, not failing). Fix:
   ```bash
   kubectl rollout restart deployment <policy-engine>-admission-controller -n <policy-engine-ns>
   ```
   Only needed on first enablement of the CRD-based component per cluster. To avoid this entirely, ensure the CRD is installed before the policy that watches it.
