# Helm Essentials Pack

The small set of Helm patterns that actually make a difference in a GitOps repo. These are the patterns the `helm-engineer` sub-agent assumes.

## Chart authoring

- Follow the existing chart layout in the target repo.
- Keep wrapper charts minimal; defer to upstream defaults wherever possible.
- Use upstream chart dependencies when wrapping third-party tools.
- Include only the values layers you actually need (env / provider / cluster).

## Wrapper chart pattern

```
charts/<name>/
├── .helmignore
├── Chart.yaml          # declares upstream chart as dependency
├── values.yaml         # minimal top-level defaults
├── templates/
│   └── namespace.yaml  # ALWAYS include explicit Namespace
└── values/
    ├── environments/   # per-env: dev / test / prod
    ├── providers/      # per-cloud: gcp / aws — only if needed
    └── clusters/  # per-cluster — only if needed
```

Not every chart needs all three subdirectories. Only create what is required.

### Chart.yaml

```yaml
apiVersion: v2
name: <chart-name>
description: A Helm chart for Kubernetes
type: application
version: <wrapper-version>     # independent of upstream
appVersion: <upstream-app-version>
dependencies:
  - name: <upstream-chart-name>
    version: <upstream-chart-version>
    repository: <upstream-helm-repo-url>
```

Keep wrapper `version` decoupled from upstream — bumping upstream should not force a wrapper-version reset.

## Hardening rules

1. **Always include an explicit Namespace template** in wrappers. Clarifies ownership, avoids `CreateNamespace=true` collisions.
2. **Verify upstream values paths.** `helm show values <repo>/<chart> --version <ver>` and confirm every override key exists.
3. **Don't override curated upstream lists/maps** unless you mean to replace the whole thing — setting these in your wrapper replaces upstream defaults.
4. **Re-render after every change.** `helm dep build && helm lint && helm template` is the minimum gate.
5. **Publish the upstream chart, not the wrapper, to an internal OCI registry** if you mirror dependencies. Publishing the wrapper creates a recursive dependency loop.
6. **Pin CI tool versions** with checksum verification (yq, kubectl) and commit-SHA pinning (third-party Actions, with a version comment).

## YAML formatting gotchas

- **Empty override files must be 0 bytes.** Helm tolerates them, `yamlfmt --lint` strips `{}` and `---` anyway. Use `truncate -s 0 <file>` or `> <file>`. Always `yamlfmt --lint` to verify.
- **`yq -i` reformats YAML.** It adds array indentation, breaking `indentless_arrays` yamlfmt configs. Use `yq` for read/parse, `sed` for write — or run `yamlfmt` after `yq -i` to restore formatting.

## CI workflows

When a chart adds an external Helm repo, register the repo URL in **every** reusable workflow that runs `helm dep build` (typically lint, release, scan). Missing one of them causes random CI failures only on certain workflows.

For wrapper charts deployed by GitOps from Git, do NOT generate a release workflow — the workflow generator's `createReleaseWorkflow` toggle should be `false`.

## Validation gates

```bash
helm dep build charts/<chart>
helm lint charts/<chart>
helm template <release> charts/<chart> -f charts/<chart>/values/environments/dev.yaml > /tmp/rendered.yaml
diff -u /tmp/before.yaml /tmp/rendered.yaml | head -200
```

For migrations:

```bash
tar -tzf charts/<chart-name>/charts/<chart>-<version>.tgz | head    # confirm pulled chart identity
```

## Upgrade gotchas

- Service names and ports can break downstream references.
- Server-side apply can fail on list merge keys.
- Immutable fields (`StatefulSet` storage size, `Service` clusterIP, `Job` template) require delete-and-recreate.
- CRDs and webhooks need ordering attention — use sync waves.

For the full upgrade flow, use the [`helm-upgrade` skill](../../skills/helm-upgrade/SKILL.md).
