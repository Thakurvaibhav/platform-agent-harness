---
name: k8s-debug
description: >-
  Debug Kubernetes workloads using read-only commands. Use for pod failures,
  CrashLoopBackOff, Pending pods, OOMKilled containers, failing health probes,
  and other workload issues. Strictly read-only — never mutate resources.
---

# Kubernetes Debug (Read-Only)

Strictly read-only. Never modify, delete, scale, restart, or patch any Kubernetes resource. The goal is to gather diagnostic information and present findings so the human can decide on remediation.

## Discipline

- `kubectl get|describe|logs|top` only.
- No `kubectl apply|create|delete|patch|replace|edit|scale|rollout|...`.
- No `helm install|upgrade|uninstall|rollback`.
- Prefix verbose read-only commands with `rtk` per [`core/protocols/rtk-command-policy.md`](../../core/protocols/rtk-command-policy.md).

## Triage workflow

### 1. State of the workload

```bash
rtk kubectl get pod <pod> -n <ns> -o wide
rtk kubectl describe pod <pod> -n <ns>
```

Look for:

- `Status`: Pending, CrashLoopBackOff, OOMKilled, Error, Completed.
- `Restart Count`: high count → flaky container.
- `Last State`: ExitCode 137 (OOM), 1 (app error), 143 (SIGTERM).
- `Events`: scheduling failures, image pull errors, probe failures.

### 2. Logs

```bash
rtk kubectl logs <pod> -n <ns> --tail=200
rtk kubectl logs <pod> -n <ns> --previous --tail=200
```

For multi-container pods:

```bash
rtk kubectl logs <pod> -n <ns> -c <container>
```

Grep for `error|warn|fail|panic|fatal|timeout`.

### 3. Probes

If the pod is `CrashLoopBackOff` but the container exits cleanly:

- `Readiness` failures keep traffic away but don't restart the pod.
- `Liveness` failures cause restarts.

Inspect probe definitions and recent failures:

```bash
rtk kubectl describe pod <pod> -n <ns> | grep -A6 "Liveness\|Readiness\|Startup"
```

### 4. Resource pressure

```bash
rtk kubectl top pod -n <ns>
rtk kubectl top pod <pod> -n <ns> --containers
rtk kubectl top node
rtk kubectl describe node <node> | grep -A5 "Allocated resources"
rtk kubectl describe pod <pod> -n <ns> | grep -A3 "Limits\|Requests"
```

Look for OOMKilled and node saturation.

**CPU throttling (CFS).** A pod that is slow/unresponsive but `Running`, not restarting, and clean in logs is often being throttled by the kernel CFS scheduler. Compare actual CPU (`top`) against the request/limit:

- Actual usage well above the CPU **request** → throttled when it tries to burst beyond its fair share on a busy node.
- A CPU **limit** is set → the container is hard-capped and throttled even when the node has spare capacity. This is the most common cause.
- Symptoms: high request latency, probe timeouts, raised error rates, but no restarts and no obvious log errors.
- In Prometheus, `container_cpu_cfs_throttled_seconds_total` rising confirms throttling.

### 5. Networking

Trace the path from ingress/gateway down to the pod.

```bash
rtk kubectl get svc -n <ns>
rtk kubectl get endpoints -n <ns>
rtk kubectl get networkpolicy -n <ns>
rtk kubectl describe ingress -n <ns>
```

Check whether the pod is in the endpoints list (it isn't if not Ready). If endpoints are empty, the Service selector matches no ready pods — cross-reference the selector against pod labels and IPs:

```bash
rtk kubectl get svc <svc> -n <ns> -o jsonpath='{.spec.selector}'
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.metadata.labels}'
rtk kubectl get pods -n <ns> -l app=<app> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'
```

Also verify the Service `targetPort` matches the container's listening port:

```bash
rtk kubectl get svc <svc> -n <ns> -o jsonpath='{.spec.ports}'
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].ports}'
```

**Gateway API (HTTPRoute).** If routing is via Gateway API rather than Ingress, verify the route's `backendRefs` point at the right Service and port, and that the route is Accepted/attached to its Gateway:

```bash
rtk kubectl get httproute -n <ns>
rtk kubectl describe httproute <route> -n <ns>
rtk kubectl get httproute <route> -n <ns> -o jsonpath='{.spec.rules[*].backendRefs}'
rtk kubectl get gateway -n <ns>
rtk kubectl describe gateway <gateway> -n <ns>
```

Look for: `backendRef` naming a wrong/missing Service or port; `ResolvedRefs=False` or `Accepted=False` in the HTTPRoute status conditions; a `parentRef` that doesn't match the Gateway; stale endpoints (endpoint IPs matching no current pod).

### 6. Recent changes

```bash
rtk kubectl describe deployment <deploy> -n <ns>     # rolloutHistory
rtk kubectl rollout history deployment/<deploy> -n <ns>
rtk kubectl get events -n <ns> --sort-by=.lastTimestamp
```

### 7. Volumes and zone-awareness

A pod stuck in `Pending` or `ContainerCreating` is often a volume problem. Zonal PVs (GCE PD, EBS) attach only to nodes in the **same zone** as the volume — a pod scheduled to another zone hangs waiting for the attach.

```bash
rtk kubectl get pvc -n <ns>
rtk kubectl describe pvc <pvc> -n <ns>
rtk kubectl get pv
rtk kubectl describe pv <pv>

# Compare the PV's zone against the node the pod landed on
rtk kubectl get pv <pv> -o jsonpath='{.spec.nodeAffinity}'
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.nodeName}'
rtk kubectl get node <node> -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}'

# A volume stuck attaching (e.g. after a node failure)
rtk kubectl get volumeattachment | grep <pv>
rtk kubectl describe volumeattachment <attachment>

# Is the StorageClass zone-aware / WaitForFirstConsumer?
rtk kubectl get storageclass
rtk kubectl describe storageclass <sc>
```

What to look for:

- PVC `Pending` — no PV matches the claim, or the StorageClass can't provision.
- PV `Released` — prior claim deleted but not recycled (check reclaim policy).
- Zone mismatch — the PV's `nodeAffinity` pins it to a zone the pod isn't in. A zonal StorageClass should use `volumeBindingMode: WaitForFirstConsumer` so the PV is provisioned in the pod's zone; if it's `Immediate`, the PV can land in the wrong zone.
- VolumeAttachment stuck — volume still attached to a dead/previous node. Force-detach (deleting the VolumeAttachment) is a **mutating** fix — recommend it, do not run it.
- `Multi-Attach error` — the volume isn't ReadWriteMany and is already attached elsewhere.

### 8. Secrets (Infisical)

If a pod fails on missing/stale env vars or mounted secrets and secrets are synced by the Infisical operator, trace the chain: InfisicalSecret CR → Kubernetes Secret → pod.

```bash
# 1. Is the InfisicalSecret CR healthy and syncing?
rtk kubectl get infisicalsecret -n <ns>
rtk kubectl describe infisicalsecret <name> -n <ns>
rtk kubectl get infisicalsecret <name> -n <ns> -o jsonpath='{.status}'

# 2. Operator logs for this secret (operator runs in its own namespace,
#    default install: infisical-operator-system)
rtk kubectl logs -n <operator-ns> -l app.kubernetes.io/name=infisical-operator --tail=200 | grep -i "<name>\|error\|fail"

# 3. Did the managed Kubernetes Secret get created/updated? (key names only)
rtk kubectl get secret <secret> -n <ns>
rtk kubectl get secret <secret> -n <ns> -o jsonpath='{.metadata.resourceVersion}'
rtk kubectl get secret <secret> -n <ns> -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}'

# 4. Does the pod reference the right secret + key?
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].env}'
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].envFrom}'
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.volumes}'
```

What to look for:

- CR status shows errors — not synced from Infisical (auth failure, wrong project/environment, missing key). Check operator logs.
- Managed Secret missing — operator hasn't created it; confirm the CR targets the right namespace.
- Secret exists but a key is absent — key not present upstream, or the CR filters keys. Diff the Secret's keys against what the pod expects (`secretKeyRef.key`).
- Pod names the wrong Secret/key — typo in `env[].valueFrom.secretKeyRef.name`/`.key`.
- Env var empty in a **running** pod — `env`-injected secrets are read only at startup; updating the Secret does not update a running pod (needs a restart — recommend, don't run). Volume-mounted secrets **do** auto-update, but with a kubelet sync delay (~60s).

Never print secret values — check existence and key names only.

## Per-symptom playbooks

Once Step 1 tells you the status, follow the matching sequence. All read-only.

**CrashLoopBackOff** — container starts, crashes, restarts with backoff.

```bash
rtk kubectl describe pod <pod> -n <ns>                       # State / Last State / Restart Count
rtk kubectl logs <pod> -n <ns> -c <container> --previous --tail=200   # the crashed run — the key one
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.status.containerStatuses[*].lastState}'
rtk kubectl get events -n <ns> --field-selector involvedObject.name=<pod> | grep -i "liveness\|unhealthy"
```

Exit code lives in `lastState.terminated.exitCode` (137 = OOM/SIGKILL, 1 = app error, 139 = segfault). `Liveness probe failed` in events means the kubelet is killing it — the app didn't crash on its own; check the probe's port/path/timeout/threshold.

**Pending** — cannot be scheduled (resource or scheduling constraint).

```bash
rtk kubectl describe pod <pod> -n <ns>                       # Events section explains why
rtk kubectl top nodes
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].resources}'
rtk kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
rtk kubectl get pvc -n <ns>                                  # unbound PVC also blocks scheduling
```

Look for `Insufficient cpu/memory`, `0/N nodes are available` (taints/affinity/resources), unbound PVCs, or node selectors matching no node.

**ImagePullBackOff / ErrImagePull** — image can't be pulled.

```bash
rtk kubectl describe pod <pod> -n <ns>                       # Events show the pull error
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].image}'
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.imagePullSecrets}'
rtk kubectl get secrets -n <ns> | grep -i pull
```

Typo in image/tag, tag absent from the registry, missing/expired pull secret, or registry unreachable (DNS/NetworkPolicy).

**Running but not Ready** — readiness failing, so no traffic.

```bash
rtk kubectl describe pod <pod> -n <ns>                       # Conditions + Events
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].readinessProbe}'
rtk kubectl logs <pod> -n <ns> -c <container> --tail=100
```

`Readiness probe failed` with an HTTP status/error, app not listening on the expected port, a dependency down, or wrong probe port/path.

**OOMKilled** — exceeded its memory limit.

```bash
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.status.containerStatuses[*].lastState.terminated.reason}'
rtk kubectl describe pod <pod> -n <ns> | grep -A3 "Limits\|Requests"
rtk kubectl top pods -n <ns> -l app=<app>
rtk kubectl logs <pod> -n <ns> -c <container> --previous --tail=200
```

Limit too low, a memory leak (usage climbs until OOM), a traffic spike, or heap misconfiguration (JVM).

**Init:Error / Init:CrashLoopBackOff** — an init container fails, so the main container never starts. Always check init containers first.

```bash
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.initContainers[*].name}'
rtk kubectl get pod <pod> -n <ns> -o jsonpath='{.status.initContainerStatuses}'
rtk kubectl logs <pod> -n <ns> -c <init-container>
```

## Pattern → cause map

| Pattern | Likely cause |
| --- | --- |
| ImagePullBackOff | Image tag missing or registry auth |
| CrashLoopBackOff, exit 137 | OOM — bump `resources.limits.memory` |
| CrashLoopBackOff, exit 1 | App startup failure — read logs |
| Pending, no events | No matching node — taints / affinity / resource requests |
| Pending, FailedScheduling | Insufficient cpu/memory — node sizing |
| Ready=false but pod Running | Readiness probe failing — endpoint not exposed |
| Restarts++ but logs clean | Liveness probe failure — increase timeout / check `/livez` |
| Endpoint missing | Pod not Ready or label mismatch with Service `selector` |
| Slow/latency, Running, no restarts, clean logs | CPU throttling (CFS) — usage above request, or a CPU limit hard-caps it |
| Pending/ContainerCreating, volume waiting | PV/pod zone mismatch or stuck VolumeAttachment — check zonal SC / `WaitForFirstConsumer` |
| PVC Pending | No matching PV or StorageClass can't provision |
| Env/secret missing or stale | InfisicalSecret CR not synced, wrong secret/key ref, or running pod needs restart to pick up new `env` |
| 5xx / no traffic via Gateway API | HTTPRoute `backendRef` wrong, or `ResolvedRefs`/`Accepted`=False |

## Output

Return findings as a structured handoff (see [`core/protocols/safety-and-handoff.md`](../../core/protocols/safety-and-handoff.md)):

```markdown
## Summary
<1-3 sentences>

## Symptoms
- <pod>: <status, restart count, exit code>

## Evidence
- `kubectl describe pod ...`: <key fact>
- `kubectl logs ... --previous`: <key fact>

## Likely cause
<one paragraph>

## Recommended next steps
1. <specific remediation>
2. <specific remediation>
```

Recommend remediation — do not perform it.

## Memory

```bash
bd remember "<workload> <issue>: root cause <X>; fix <Y>" --key <repo>/trouble/<workload>-<issue>
```
