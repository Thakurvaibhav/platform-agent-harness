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
rtk kubectl top node
rtk kubectl describe node <node> | grep -A3 "Allocated"
```

Look for OOMKilled and node saturation.

### 5. Networking

```bash
rtk kubectl get svc -n <ns>
rtk kubectl get endpoints -n <ns>
rtk kubectl get networkpolicy -n <ns>
rtk kubectl describe ingress -n <ns>
```

Check whether the pod is in the endpoints list (it isn't if not Ready).

### 6. Recent changes

```bash
rtk kubectl describe deployment <deploy> -n <ns>     # rolloutHistory
rtk kubectl rollout history deployment/<deploy> -n <ns>
rtk kubectl get events -n <ns> --sort-by=.lastTimestamp
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
