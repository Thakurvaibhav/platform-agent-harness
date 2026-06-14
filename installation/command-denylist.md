# Command Denylist Starter

The harness defaults to read-only behavior. Translate this list into your runtime's permission / denylist format (see your adapter README).

## Always deny

| Command pattern | Why |
| --- | --- |
| `kubectl apply *` | Cluster mutation |
| `kubectl create *` | Cluster mutation |
| `kubectl delete *` | Cluster mutation |
| `kubectl patch *` | Cluster mutation |
| `kubectl replace *` | Cluster mutation |
| `kubectl edit *` | Interactive + mutation |
| `kubectl scale *` | Cluster mutation |
| `kubectl rollout *` | Cluster mutation |
| `kubectl set *` | Cluster mutation |
| `kubectl annotate *` | Cluster mutation |
| `kubectl label *` | Cluster mutation |
| `kubectl taint *` | Cluster mutation |
| `kubectl cordon *` / `uncordon *` / `drain *` | Cluster mutation |
| `helm install *` | Cluster mutation |
| `helm upgrade *` | Cluster mutation |
| `helm uninstall *` | Cluster mutation |
| `helm rollback *` | Cluster mutation |
| `helm delete *` | Cluster mutation |
| `git push --force *` / `--force-with-lease * main *` / `* master *` | History rewrite |
| `git push * main *` / `git push * master *` | Protected branch push |
| `bd edit *` | Opens `$EDITOR` (interactive); blocks the agent |
| `rm -rf /` | Catastrophic |
| `rm -rf ~/` | Catastrophic |
| `rm -rf *` (broad globs) | Catastrophic |
| `chown -R *` (broad targets) | Privilege escalation risk |
| `chmod -R *` (broad targets) | Permission corruption risk |

## Claude Code `permissions.deny`

The canonical translation of the **Always deny** mutating set into Claude Code's `.claude/settings.json` → `permissions.deny`. Keep this in sync with the full block in [`adapters/claude-code/README.md`](../adapters/claude-code/README.md). The `rm`/`chown`/`chmod`/pipe entries above are enforced by the runtime's own destructive-command gate rather than enumerated here.

```json
"deny": [
  "Bash(git push origin main)",
  "Bash(git push origin main:*)",
  "Bash(git push origin master)",
  "Bash(git push origin master:*)",
  "Bash(git push --force origin main)",
  "Bash(git push --force origin master)",
  "Bash(git push --force-with-lease origin main)",
  "Bash(git push --force-with-lease origin master)",
  "Bash(kubectl apply:*)",
  "Bash(kubectl create:*)",
  "Bash(kubectl delete:*)",
  "Bash(kubectl patch:*)",
  "Bash(kubectl replace:*)",
  "Bash(kubectl edit:*)",
  "Bash(kubectl scale:*)",
  "Bash(kubectl rollout:*)",
  "Bash(kubectl set:*)",
  "Bash(kubectl annotate:*)",
  "Bash(kubectl label:*)",
  "Bash(kubectl taint:*)",
  "Bash(kubectl cordon:*)",
  "Bash(kubectl uncordon:*)",
  "Bash(kubectl drain:*)",
  "Bash(helm install:*)",
  "Bash(helm upgrade:*)",
  "Bash(helm uninstall:*)",
  "Bash(helm rollback:*)",
  "Bash(helm delete:*)",
  "Bash(bd edit:*)"
]
```

## Conditional deny

Allow only after explicit confirmation in the prompt:

| Command pattern | Why conditional |
| --- | --- |
| `git push --force-with-lease` | Allowed on your own feature branch only |
| `git rm -r *` | Safer alternative to `rm -rf`; still destructive |
| `helm template * | kubectl apply -f -` | The pipe escapes read-only intent |

## Always allow (read-only)

- `kubectl get|describe|logs|top|explain`
- `helm template|lint|show values|dependency build|dependency update|show chart|show readme`
- `git status|diff|log|show|branch|remote -v|stash list`
- `gh pr|issue|run view|list|diff`
- `docker ps|images|logs|inspect`
- `terraform plan` (no `apply`)
- `gcx --agent ... -o json` (read paths only)

## Sanitization commands

Pre-publish scanners should be allowed and used (see [`sanitization/prepublish-checklist.md`](../sanitization/prepublish-checklist.md)):

- `trufflehog filesystem .`
- `gitleaks detect --no-git`
- `rg`, `grep`, `find` (read-only)
