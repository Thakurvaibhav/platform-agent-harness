# Kubernetes Safety Pack

Read-only defaults, blast-radius rules, and a small set of patterns that keep agents from breaking clusters.

## Hard rules

- **Read-only by default.** Allowed: `get`, `describe`, `logs`, `top`, `explain`.
- **Never** `apply|create|delete|patch|replace|edit|scale|rollout|set|annotate|label|taint|cordon|uncordon|drain`.
- **Never** `helm install|upgrade|uninstall|rollback`.
- **Always** pass `--context <cluster>` explicitly for multi-cluster setups. Never rely on current-context.
- **Never** `kubectl exec` into a Pod and run mutating commands.

## Context awareness

Before any cluster operation:

```bash
rtk kubectl config current-context     # confirm you are on the intended cluster
rtk kubectl cluster-info                # quick sanity
```

For multi-context inspection, prefer explicit `--context`:

```bash
rtk kubectl --context <cluster> get pods -n <ns>
```

## Multi-cluster awareness

Treat each environment as a distinct blast radius:

| Env | Typical purpose |
| --- | --- |
| `ops` | Control plane for GitOps tooling (ArgoCD, IRM). No workloads. |
| `dev` | Fast iteration, debug logging, relaxed limits. |
| `stag` | Production-like, soak testing. |
| `prod` | Strict settings, HA, no manual changes. |

For production clusters, even read-only queries should be scoped (specific namespace / pod) — broad `kubectl get` against a busy prod cluster wastes context.

## Patterns

### Verify pod health post-deploy

```bash
rtk kubectl get pods -n <ns> --context <cluster>
rtk kubectl describe pod <pod> -n <ns> --context <cluster>
rtk kubectl logs <pod> -n <ns> --context <cluster> --tail=200 | grep -E 'error|warn|fail|panic'
```

All Ready, zero restarts, operator logs clean.

### Verify CRDs after operator deploy

```bash
rtk kubectl get crd --context <cluster> | grep <tool>
rtk kubectl get <cr-kind> -A --context <cluster>
```

ArgoCD "Synced/Healthy" does NOT mean Custom Resources reconcile correctly. Always check CR `status.conditions` directly.

### Service connectivity check

```bash
rtk kubectl get svc -n <ns> --context <cluster>
rtk kubectl get endpoints -n <ns> --context <cluster>
```

If a pod is `Ready=false`, it will not appear in `endpoints`. The Service silently routes around it.

## When the user asks for a mutation

If the user asks the agent to make a change that would mutate cluster state, the agent must:

1. Refuse the direct mutation.
2. Generate the corresponding GitOps change (Helm values, ArgoCD Application, manifest edit) in the appropriate repo.
3. Hand the change to the user as a PR.

This is the entire point of the GitOps-first defaults — mutations flow through Git, not `kubectl`.

## Reference companion

For a public, sanitized companion repo using this exact safety model, see [Thakurvaibhav/k8s](https://github.com/Thakurvaibhav/k8s) — a GitOps Platform-in-a-Box with App-of-Apps, Envoy Gateway, Prometheus/Thanos, Kyverno, and Sealed Secrets.
