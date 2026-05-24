# Validation Contract Template

A validation contract is a runnable artifact. It lists numbered assertions, each with a pass/fail criterion and required evidence.

```markdown
# Validation Contract: <feature / change name>

## Scope
- Target: <repo | service | cluster | dashboard>
- Surface(s): <CLI | API | UI | Kubernetes | GitOps | observability>
- Preconditions:
  - <env requirement>
  - <auth requirement>
- Out of scope:
  - <what we deliberately do not validate>

## Assertions

### 1. <short name>
- **Claim**: <what should be true>
- **How to test**: <exact command / query / API call>
- **Pass criterion**: <precise observable>
- **Required evidence**: <command output | screenshot | response JSON>

### 2. <short name>
- **Claim**: ...
- **How to test**: ...
- **Pass criterion**: ...
- **Required evidence**: ...

### 3. <short name>
- **Claim**: ...
- **How to test**: ...
- **Pass criterion**: ...
- **Required evidence**: ...
```

## Example assertion (Kubernetes surface)

```markdown
### 3. ServiceMonitor scrapes <service>
- **Claim**: Prometheus discovers <service>'s `/metrics` endpoint and scrapes it.
- **How to test**:
  rtk kubectl get servicemonitor -n <ns> --context <cluster> -o yaml | yq '.items[] | select(.metadata.name == "<service>")'
  rtk gcx --agent metrics query -d <prom-uid> 'up{job="<service>"}' -o json --since 5m
- **Pass criterion**: ServiceMonitor exists with `selector` matching `<service>`'s labels; `up{job="<service>"} == 1` for at least one target.
- **Required evidence**: ServiceMonitor YAML; PromQL response showing `up=1`.
```

## Status meanings

- `pass` — observed behavior matches the contract.
- `fail` — observed behavior contradicts the contract.
- `blocked` — prerequisite unavailable or unsafe to proceed.
- `skipped` — explicitly out of scope or not applicable to this run.

## Running the contract

Use the [`contract-validation` skill](../skills/contract-validation/SKILL.md). For multi-target runs, pair with [`core/protocols/parallel-dispatch.md`](../core/protocols/parallel-dispatch.md).

## Output

Reports follow [`validation-report.template.json`](validation-report.template.json) for machine-readable output, or the standard handoff contract for human review.
