---
name: helm-upgrade
description: >-
  Upgrade a Helm chart dependency (subchart bump, appVersion bump, repo
  migration) safely in a GitOps repo. Covers research, breaking-change
  analysis, cross-component reference checks, values migration, local
  validation, PR creation, and deployment notes.
---

# Helm Upgrade

Use this skill when the user wants to upgrade a Helm subchart version, bump `appVersion`, migrate a chart to a new repo, or perform any observability / infrastructure dependency upgrade.

**Do not use** for first-time chart installs (no existing version to upgrade from) or for direct `helm install / upgrade` against a cluster.

Prefix verbose read-only commands with `rtk` per [`core/protocols/rtk-command-policy.md`](../../core/protocols/rtk-command-policy.md).

**Fast-path for patch bumps:** If the upgrade is a patch bump (e.g. `1.5.19` → `1.5.20`) whose only change is an `appVersion` bump with no chart template changes, you can skip Steps 5b–6 and go straight to the cross-component check (Step 3). Confirm this from the upstream release notes first — if the only line is "bump app to vX.Y.Z", the fast-path applies.

## Steps

### 1. Identify the upgrade target

```bash
# Current version
yq '.dependencies[] | select(.name == "<chart>") | .version' charts/<chart-name>/Chart.yaml

# Latest available
helm search repo <repo>/<chart> --versions | head
```

### 2. Read upstream release notes

For every version between current and target, read the upstream CHANGELOG and release notes. Flag:

- Breaking changes.
- Removed values.
- New required values.
- CRD changes.
- Container image / SBOM changes.
- **Service name / port changes** (see Step 5b — the most commonly missed breaking change).

### 3. Cross-component reference check

Other charts may hard-code endpoints (service name + port) that break when the component you upgrade renames or re-ports a service. Use the Grep tool (or `rg`), not shell `grep`, and exclude `Chart.lock` matches:

```bash
rg -n "<chart-name>" charts/ --glob '*.yaml'
rg -n "<chart-name>" .github/workflows/

# Confirm every referenced value path still exists in the new version
helm show values <repo>/<chart> --version <new-version> | grep -F "<path>"
```

Common reference patterns to check:

- **otel collector endpoints** — exporter/backend URLs in `charts/otel/values/` pointing at the upgraded service.
- **Grafana datasource URLs** — `lokiUrl` / `tempoUrl` / `mimirDatasourceUrl` style keys in chart values.
- **Alertmanager / ruler URLs** — configs pointing at an alertmanager service.

### 4. Edit `Chart.yaml`

```yaml
dependencies:
  - name: <chart>
    version: <new-version>      # was <old-version>
    repository: <upstream-helm-repo-url>
```

If `appVersion` is independently tracked, bump it too. If the upstream repo moved, update `repository` here **and** add the new `helm repo add` line to the chart-lint CI workflow (see Common gotchas → *CI lint fails on new Helm repos*).

### 5. Local validation

```bash
helm dep build charts/<chart-name>
helm lint charts/<chart-name> --skip-schema-validation
helm template <release> charts/<chart-name> -f charts/<chart-name>/values/environments/dev.yaml --skip-schema-validation
```

If a repo YAML formatter exists (e.g. `yamlfmt`), run it in `--lint` mode too.

For each environment that will receive the upgrade, render and inspect the diff:

```bash
helm template <release> charts/<chart-name> -f <values-before>.yaml > /tmp/before.yaml
helm template <release> charts/<chart-name> -f <values-after>.yaml > /tmp/after.yaml
diff -u /tmp/before.yaml /tmp/after.yaml | less
```

### 5b. Detect service name / port changes (SSA merge safety)

Render the **old** chart before editing `Chart.yaml`, and the **new** chart after, then diff. This catches service renames, port renumbering, and the Server-Side-Apply hazard below.

```bash
# BEFORE editing Chart.yaml
helm template charts/<chart-name> --skip-schema-validation > /tmp/old-manifests.yaml
# AFTER editing Chart.yaml + helm dep build
helm template charts/<chart-name> --skip-schema-validation > /tmp/new-manifests.yaml
diff /tmp/old-manifests.yaml /tmp/new-manifests.yaml
```

**SSA port-list merge conflict (critical for ArgoCD with `ServerSideApply=true`).** SSA merges a Service's `spec.ports` list by **port number** (the merge key), not by port name. If an upgrade moves a named port to a different number (e.g. `http-metrics` from `3100` to `3200`), SSA keeps *both* entries, producing duplicate port names that Kubernetes rejects with a "Duplicate value" error. The same applies to container-port lists in Deployments/StatefulSets.

Detect it by comparing each named port's number between old and new:

```bash
python3 -c "
import yaml
for path, label in [('/tmp/old-manifests.yaml','OLD'), ('/tmp/new-manifests.yaml','NEW')]:
    with open(path) as f:
        for doc in yaml.safe_load_all(f):
            if not doc or doc.get('kind') != 'Service': continue
            name = doc['metadata']['name']
            for p in doc.get('spec',{}).get('ports',[]):
                print(f'{label} {name}: {p[\"name\"]}={p[\"port\"]}')
"
```

If any named port changed its number, the auto-sync will fail. **Resolution:** a manual ArgoCD Sync with the **Replace** option (bypasses SSA, does a full `kubectl replace`). Document this in the PR.

### 6. Look for immutable-field changes across all resource kinds

Many Kubernetes resources have fields that cannot change after creation. A chart upgrade that mutates them causes ArgoCD sync failures. The render diff (Step 5b) is your last chance to spot them.

| Resource | Immutable fields | Resolution |
|---|---|---|
| **StatefulSet** | `serviceName`, `selector`, `volumeClaimTemplates[*].spec` (accessModes, storageClassName, resources), `podManagementPolicy` | Merge PR first, then `kubectl delete statefulset <name> --cascade=orphan`; ArgoCD self-heal recreates |
| **Deployment** | `selector` | ArgoCD Sync with **Replace**, or delete + recreate |
| **DaemonSet** | `selector` | Same as Deployment |
| **Job** | `selector`, `template`, `completionMode` | Delete the old Job, let ArgoCD recreate |
| **CronJob** | `jobTemplate.spec.selector` | Delete and recreate |
| **Service** | `clusterIP`, `type` (some transitions), `ipFamilyPolicy` | ArgoCD Sync with **Replace**, or delete + recreate |
| **PVC** | `storageClassName`, `accessModes`, `volumeMode` (storage can expand, not shrink) | Cannot simply delete — requires a data-migration plan |

Automated check against the rendered manifests from Step 5b:

```bash
python3 -c "
import yaml, json
IMMUTABLE = {
    'StatefulSet': {'serviceName','selector','volumeClaimTemplates','podManagementPolicy'},
    'Deployment':  {'selector'},
    'DaemonSet':   {'selector'},
    'Job':         {'selector','template','completionMode'},
    'Service':     {'clusterIP','clusterIPs','ipFamilyPolicy','ipFamilies','type'},
}
def load(path):
    out = {}
    with open(path) as f:
        for doc in yaml.safe_load_all(f):
            if not doc: continue
            out[f\"{doc.get('kind','')}/{doc.get('metadata',{}).get('name','')}\"] = (doc.get('kind',''), doc.get('spec',{}))
    return out
old, new = load('/tmp/old-manifests.yaml'), load('/tmp/new-manifests.yaml')
found = False
for key in sorted(set(old) & set(new)):
    kind, os_ = old[key]; _, ns_ = new[key]
    for field in IMMUTABLE.get(kind, set()):
        if json.dumps(os_.get(field), sort_keys=True) != json.dumps(ns_.get(field), sort_keys=True):
            print(f'IMMUTABLE CHANGE: {key} spec.{field}'); found = True
print('No immutable field changes detected' if not found else '\nACTION REQUIRED: apply the resolution per kind above')
"
```

Don't assume only one field or one resource is affected — a single subchart upgrade can require orphan-deleting one StatefulSet for `serviceName` **and** another for a `volumeClaimTemplates.accessModes` change at the same time.

### 7. Verify the pulled tgz

After `helm dep build`, confirm the resolved tarball is the upstream chart, not a copy of your wrapper:

```bash
tar -tzf charts/<chart-name>/charts/<chart>-<version>.tgz | head
```

### 8. Review the ArgoCD App-of-Apps diff

Local `helm template` cannot see SSA merge outcomes, operator-injected fields, or cross-component side effects. The App-of-Apps diff can. It fetches the **fully rendered Kubernetes manifests** ArgoCD would apply — for both the live revision and the PR branch (`argocd app manifests <app> --revision <branch>`) — and runs `dyff` between them. It shows real resource-level changes (Deployments, Services, CRDs, ConfigMaps), not just Application-spec changes.

**Option A — CI diff (preferred).** If the repo has an app-of-apps diff workflow (e.g. `argocd_app_of_apps_diff.yaml`) that runs on PRs touching `charts/**`, wait for its per-cluster `dyff` comment and review it. That is the authoritative view of what ArgoCD will apply.

*Large-diff fallback:* CRD-heavy upgrades can exceed the platform's comment size limit and fail to post. Read the diff from the CI job logs instead:

```bash
gh run view <run-id> --json jobs --jq '.jobs[] | select(.name|contains("<cluster>")) | .databaseId'
gh api repos/<owner>/<repo>/actions/jobs/<job-id>/logs 2>/dev/null | sed 's/^[0-9TZ:.-]* //'
```

**Option B — run the diff locally** (requires the `argocd` CLI, `dyff`, network access to the ArgoCD endpoint, and credentials):

```bash
# Which clusters deploy this component?
for f in charts/argo-apps/values.*.yaml; do
  cluster=$(basename "$f" | sed 's/values\.//;s/\.yaml//')
  grep -q "^<component>:" "$f" 2>/dev/null && echo "$cluster"
done

argocd --grpc-web login argocd-<cluster>.<internal-domain> --username <user> --password <password>
# point the diff action at your branch, then run it (unset the token to skip PR-comment posting)
```

**What to look for:** `spec.ports.*.port` changes on Services (SSA risk), service renames (cross-component breakage), new/removed resources, immutable-field changes on StatefulSets, container-port changes, CRD schema changes, and operator Deployment image/arg changes.

### 9. Pre-merge gate

Confirm **all** of these before requesting review or merging (see [`core/protocols/safety-and-handoff.md`](../../core/protocols/safety-and-handoff.md)):

- [ ] Local validation passed (`helm dep build`, `template`, `lint`, formatter).
- [ ] `git diff` shows only expected files; no secrets or credentials; `Chart.lock` updated correctly.
- [ ] ArgoCD app-of-apps diff reviewed (CI comment or job logs) — no unexpected resource changes.
- [ ] CI checks pass (chart-lint, YAML formatting).
- [ ] SSA port conflicts and immutable-field changes are either absent or documented with a resolution.
- [ ] Any required manual post-merge steps are written into the PR description.

If the diff shows unexpected changes (new permadiffs, resource deletions, port conflicts), investigate before merging — do not assume they resolve themselves.

### 10. Open the PR

Use the [`create-pr`](../create-pr/SKILL.md) skill. Keep each component upgrade in its own PR for a clean rollback. Reference `<TICKET>` in the branch name and commit. The PR description must include:

- Old → new version.
- Breaking changes from the CHANGELOG.
- Values changes needed (with file paths).
- Render-diff / app-of-apps diff summary and which clusters are affected.
- Deployment notes (e.g. "requires ArgoCD Sync with **Replace** for `<service>`", or "orphan-delete `<statefulset>` after merge").

Include a collapsible changelog so it doesn't clutter the description:

```markdown
<details>
<summary>Application changelog (old_version -> new_version)</summary>

**Chart changes:** template/values-schema changes, or "None" for a pure appVersion bump.

**Application changes** (spans vX.Y.Z through vA.B.C):
- Features / Fixes / Potentially breaking
</details>
```

### 11. Memory

```bash
bd remember "<chart> upgrade <old-version> → <new-version>: <key takeaway>" \
  --key <repo>/upgrade/<chart>-<new-version>
```

## Zero-downtime service / port migration

When Step 5b shows a service **rename** or a **port renumber** that other components depend on, don't do it in one shot. Split into independently-merged, independently-validated PRs so there is never a window where consumers point at a service that doesn't exist yet:

1. **Enable the new service alongside the old one** — both listen; nothing consumes the new one yet.
2. **Repoint every cross-component reference** (from Step 3) at the new service name/port.
3. **Disable the old service** once nothing references it.
4. **Bump the chart version** (or fold this into the earliest PR if the new service ships with the new version).

For a pure port renumber under SSA, the multi-PR dance still can't avoid the duplicate-port-name merge; plan the manual **Replace** sync (Step 5b) as part of the cutover.

## Post-merge monitoring & rollback

**Deployment awareness first.** Not every chart deploys to dev before prod. Check which clusters actually receive it:

```bash
for f in charts/argo-apps/values.*.yaml; do
  cluster=$(basename "$f" | sed 's/values\.//;s/\.yaml//')
  grep -q "^<component>:" "$f" 2>/dev/null && echo "$cluster"
done
```

If a component only deploys to a production cluster (e.g. `prod-01`), merging to the default branch goes straight to production with no dev soak — take extra care.

**After the sync:** verify pods are healthy, check for ArgoCD permadiffs (type mismatches, operator-injected fields), verify data flow end-to-end (metrics/logs/traces as applicable), and watch for alert regressions for ~24h.

**If the sync fails** (immutable field, SSA conflict): read the error (`argocd app get <app>`), apply the documented resolution if it's a known case, and do **not** blind force-sync an unexpected failure — investigate first.

**If pods crash-loop after sync:** check `kubectl logs <pod> -n <ns> --previous`. Fix forward with a new commit if it's a config issue; otherwise revert.

**Revert procedure:**

```bash
git log --oneline --merges -5          # find the merge commit
git revert -m 1 <merge-commit-sha>     # new commit, preserves history
git push origin <default-branch>
```

ArgoCD auto-syncs the revert, rolling back to the previous chart version. StatefulSets that were orphan-deleted during the upgrade are recreated with the old spec.

**Escalate vs. self-fix:** self-fix permadiffs, config typos, missing values, and known immutable-field cases; escalate data loss, persistent crash-loops after revert, PVC/storage issues, and cross-component outages spanning multiple services.

## Common gotchas

Patterns that have caused real production issues:

- **SSA port-list merge conflicts** — changing a named port's number under `ServerSideApply=true` leaves duplicate port names; Kubernetes rejects it. Fix: ArgoCD Sync with **Replace**. Always compare rendered port numbers (Step 5b).
- **otel collector endpoints break silently** — when a backend renames/removes a service, otel collectors exporting to it fail quietly or queue data instead of erroring loudly. Grep `charts/otel/values/` for the old endpoint before merging.
- **Datasource URLs with port changes** — an upstream chart may change its default listen port; the rendered Service port moves but the Grafana datasource URL in your values still points at the old one. Diff rendered Services.
- **Integer vs. string permadiffs** — operators sometimes store a value as a string where Helm renders an integer (`cpu: 1` vs `cpu: "1"`), producing a perpetual ArgoCD diff. Quote numeric values to match what the operator stores.
- **Helm hook annotations block ArgoCD self-heal** — if upstream defaults add `helm.sh/hook` annotations, ArgoCD treats those resources as hooks, not managed resources, and won't reconcile them on self-heal. Check for and remove unexpected hook annotations.
- **CI lint fails on new Helm repos** — after a repo migration, CI has no `helm repo add` for the new URL and dep resolution fails. Add the new repo to the chart-lint workflow in the same PR.

## What not to do

- Don't skip the upstream changelog. "It's just a patch" has caused outages.
- Don't bundle unrelated component upgrades in one PR — keep each isolated for clean rollback.
- Don't assume service names and ports are stable across major versions. Always render-diff.
- Don't forget cross-component references — the upgraded component may be fine while something pointing at it breaks.
- Don't force-sync an unexpected ArgoCD failure. Investigate first.

## Pre-completion checklist

1. `helm dep build && helm lint && helm template` clean for every changed chart.
2. Render diff (Step 5b) inspected; SSA port conflicts and immutable-field changes handled or documented.
3. Cross-component references re-verified post-upgrade.
4. ArgoCD app-of-apps diff reviewed; no unexpected resource changes.
5. CI repos still registered if the upstream URL changed.
6. ServiceMonitor / metrics paths still valid.
7. Immutable-field changes and required manual steps flagged in the PR with a rollout plan.
