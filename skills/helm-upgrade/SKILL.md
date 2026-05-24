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

### 3. Cross-component reference check

```bash
# Find every reference to the chart's values keys
rg -n "<chart-name>" charts/
rg -n "<chart-name>" .github/workflows/

# Confirm all referenced value paths still exist in the new version
helm show values <repo>/<chart> --version <new-version> | grep -F "<path>"
```

### 4. Edit `Chart.yaml`

```yaml
dependencies:
  - name: <chart>
    version: <new-version>      # was <old-version>
    repository: <upstream-helm-repo-url>
```

If `appVersion` is independently tracked, bump it too.

### 5. Local validation

```bash
helm dep build charts/<chart-name>
helm lint charts/<chart-name>
helm template <release> charts/<chart-name> -f charts/<chart-name>/values/environments/dev.yaml
```

For each environment that will receive the upgrade, render and inspect the diff:

```bash
helm template <release> charts/<chart-name> -f <values-before>.yaml > /tmp/before.yaml
helm template <release> charts/<chart-name> -f <values-after>.yaml > /tmp/after.yaml
diff -u /tmp/before.yaml /tmp/after.yaml | less
```

### 6. Look for immutable-field changes

The render diff is your last chance to spot:

- StatefulSet `volumeClaimTemplates` size changes.
- Service `clusterIP` changes.
- `Selector` changes.
- `Job` template changes (Jobs are immutable; recreate required).

If immutable fields change, the upgrade may need a delete-and-recreate path. Plan accordingly.

### 7. Verify the pulled tgz

After `helm dep build`, confirm the resolved tarball is the upstream chart, not a copy of your wrapper:

```bash
tar -tzf charts/<chart-name>/charts/<chart>-<version>.tgz | head
```

### 8. Open the PR

Use the [`create-pr`](../create-pr/SKILL.md) skill. The PR description must include:

- Old → new version.
- Breaking changes from the CHANGELOG.
- Values changes needed (with file paths).
- Render diff summary.
- Deployment notes (e.g. "requires delete-and-recreate for `<resource>`").

### 9. Memory

```bash
bd remember "<chart> upgrade <old-version> → <new-version>: <key takeaway>" \
  --key <repo>/upgrade/<chart>-<new-version>
```

## Pre-completion checklist

1. `helm dep build && helm lint && helm template` clean for every changed chart.
2. Render diff inspected and explained in the PR.
3. Cross-component references re-verified post-upgrade.
4. CI repos still registered if the upstream URL changed.
5. ServiceMonitor / metrics paths still valid.
6. Immutable-field changes flagged in the PR with a rollout plan.
