# Helm, YAML & CI Learnings

Numbered, append-only. **Update the existing entry — never duplicate.**

## YAML formatting

1. **Empty YAML override files must be 0 bytes.** When creating an empty values file (e.g. `values/clusters/<cluster>.yaml` with no overrides), the file must be completely empty. Do NOT use `{}` or `---` — most formatters strip both to empty anyway. Use `truncate -s 0 <file>` or `> <file>`. Always run `yamlfmt --lint` to verify.

2. **yamlfmt typically uses `indentless_arrays: true`** in many GitOps repos. When writing values files with list items, use indentless style:

   ```yaml
   paths:
   - "/etc/shadow"    # correct
   ```

   NOT indented style (`  - "/etc/shadow"`). Match what the repo formatter expects.

## Chart dependencies & publishing

3. **Always run `helm dep build` before lint/template.** Charts with dependencies will fail lint and template without building deps first. The CI workflows always do this — match locally.

4. **OCI registry: publish the upstream chart, not the wrapper.** When publishing a dependency to an internal OCI registry, always publish the upstream chart (from `helm pull`), NOT the wrapper chart. Publishing the wrapper creates a recursive dependency.

5. **Decouple wrapper chart version from upstream version.** Use an independent versioning scheme for wrapper charts (e.g. `0.1.x`) to avoid collisions when publishing to the same OCI registry.

## Values & overrides

6. **Avoid overriding upstream list/map defaults unless necessary.** Many upstream charts have curated default lists. Setting these in wrapper `values.yaml` **replaces** the entire upstream default rather than extending it. Only override when you explicitly need to, and include the upstream defaults too.

7. **Always verify value overrides render with `helm template`.** After changing value paths or chart dependencies, run `helm template` and confirm the rendered output contains your overrides. Values at the wrong nesting depth will silently fall back to upstream defaults.

## Git & CI

8. **Reusable workflows cannot use local composite actions** when called via `uses: ./.github/actions/*`. GitHub resolves these paths from the workspace, not the workflow's source ref. Either inline steps or call scripts directly.

9. **Pin tool downloads and third-party Actions.** Use specific versions with checksum verification for tool downloads (yq, kubectl). Pin third-party Actions to commit SHAs with version comments (e.g. `uses: actions/checkout@abc123 # v6`).

10. **When a reusable workflow is referenced by branch name**, the branch gets deleted on merge, causing `startup_failure` in all consumers. Always pin to commit SHA.

## YAML tooling

11. **`yq -i` reformats YAML.** It adds array indentation, breaking `indentless_arrays` yamlfmt configs. Use the hybrid pattern: `yq` for reading/parsing, `sed` for writing — or run `yamlfmt` after `yq -i` to restore formatting.
