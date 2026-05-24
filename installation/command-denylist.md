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
| `git push --force *` (any branch) | History rewrite |
| `git push * main *` / `git push * master *` | Protected branch push |
| `rm -rf /` | Catastrophic |
| `rm -rf ~/` | Catastrophic |
| `rm -rf *` (broad globs) | Catastrophic |
| `chown -R *` (broad targets) | Privilege escalation risk |
| `chmod -R *` (broad targets) | Permission corruption risk |

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
