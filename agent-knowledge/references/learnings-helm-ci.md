# Helm, YAML & CI Learnings

See also: `learnings-argocd.md`, `learnings-progressive-delivery.md`, `learnings-envoy-gateway.md`, `learnings-crossplane.md`, `learnings-terraform.md`, `learnings-workload-debug.md`

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

## Values & overrides (continued)

12. **Sprig's `merge(dst, src)` has the FIRST argument win on key conflicts; the second only fills in missing keys — the opposite of `mergeOverwrite(dst, src)`, where the second wins.** When you want "A always wins, B only fills in what A doesn't have," write `merge(A, B)`. The common bug is reaching for `merge` expecting the thing you pass second (the "override") to win — it will not; the base wins and the override is silently ignored wherever both set the same key. Use `mergeOverwrite` whenever the second argument is meant to override the first.

13. **Helm's `required` function does not reject an empty list or empty map — only `nil` — so a Helm guard fronting a field that a CRD marks `minItems`/`minLength` just moves the failure from render-time to apply-time, and makes it worse.** `{{ required "msg" $x.access }}` passes cleanly when `access: []`, rendering a valid-looking object with exit code 0. If the CRD declares `minItems: 1`, the apiserver then rejects the object at apply — and depending on your GitOps tooling, that can fail the entire application rather than just the one resource, which is strictly worse than the loud render-time failure the guard was meant to produce. Fix that keeps the message and stays one expression: `required "msg" (empty $x.access | ternary nil $x.access)` — `empty` catches `nil`, `[]`, `{}`, and `""` alike. Verify the guard actually fires by rendering WITH the empty value and asserting a non-zero exit — a `required` guard that looks present in the template is not proof it fires on the input you care about.


## Helm template rendering mechanics

14. **Helm renders templates in REVERSE-alphabetical path order, which inverts the naming convention you'd naturally reach for when writing an observation probe.** `helm.sh/v3/pkg/engine` sorts templates by path depth descending, then lexicographically descending, so `templates/zzz-probe.yaml` renders BEFORE `templates/serviceaccount.yaml`, and `templates/aaa-probe.yaml` renders LAST. This silently inverts any probe meant to observe state that an *earlier* template is supposed to have already mutated — for example, proving that a Sprig `merge` call mutates its first argument in place (Sprig's `merge` does mutate its first argument, so if that argument is a pointer into `.Values`, the mutation is visible to every template rendered afterward). A probe named `zzz-*` in that scenario sees clean state both before and after the fix (false negative, the whole harness is vacuous); a probe named `aaa-*` sees the real pre-fix pollution. Name any cross-template observation probe `aaa-*` so it renders first, not last.

15. **`helm template --show-only <target> --output-dir <dir>` together: Helm ignores `--show-only`, prints a spurious `Error: could not find template <target> in chart` to stderr, and still writes ALL rendered templates to the output directory — including the one you asked for.** The error looks fatal but is harmless; the fix is to ignore it and read the specific per-file YAML directly off disk in the output directory rather than trying to combine the two flags. Useful as a general workaround whenever a full-stream render is too large or noisy to grep reliably: render everything to `--output-dir` once, then read individual template outputs natively. **UNVERIFIED at source level** -- this claim carries no version pin or source citation; confirm against the tool's own source at your pinned version before relying on it.

16. **Helm `define` names are global per RELEASE, not per chart — an umbrella chart with unprefixed helper names in sibling subcharts has a latent template-namespace collision.** If two subcharts under one umbrella each `define` a helper with the same bare name, they collide at render time and the last one parsed wins — so a chart can silently render a SIBLING chart's template logic instead of its own. Identical bodies are harmless by coincidence; divergent bodies are a live, silent defect. Detect it structurally, without rendering anything, by hashing the body of every `define` across the whole dependency set and flagging name collisions with differing bodies. Fix direction: prefix every `define` with the owning chart's name. The broader consequence: "this chart's template is correct in isolation" is not a statement about what the umbrella actually renders once it's a dependency.


## Validation depth & testing

17. **In `helm-unittest` 1.1.1, negative assertions are VACUOUS on a path that doesn't exist at all — the common "isNotEmpty + notMatchRegex over a wildcard path" idiom used to prove "no bad values are present" proves nothing if the path is simply absent.** Verified with an isolated probe chart: `isNotEmpty` PASSES against a nonexistent path, `notMatchRegex` over an absent wildcard path PASSES, and `isNull` also passes on an absent path — deleting the entire block the test is supposed to be sweeping leaves all three green. What DOES fail correctly on an absent path: `contains` (both full-object and subset forms) and `lengthEqual`, which both error with an explicit "unknown path" rather than silently passing. Rule: every negative or sweep-style assertion needs a POSITIVE anchor on the same path inside the same test case — a sibling test elsewhere in the suite proves nothing about this one's non-vacuity. Prefer `contains` with a subset match on a stable value (e.g. one field known to always be present) so the anchor doesn't pin an exact count or break on unrelated message rewording.

18. **Never split a multi-document Helm render on a literal `"---\n"` separator — an embedded YAML block scalar can contain lines that look exactly like a document separator, and a naive split yields bogus scalar chunks.** A multi-line string value (a script, a config blob) inside `|` or `>` block scalar syntax can legally contain a line of three dashes, and any tool that treats that literal string as a document boundary silently mis-splits the stream. Parse the whole stream with a real multi-document-aware YAML loader (e.g. `yaml.safe_load_all`) for semantic validation; if you genuinely need exact source-byte slicing per document, use the loader's node start/end marks rather than string-splitting. Hard-fail on parse errors and on chunks that don't look like a resource, rather than silently skipping them — a silently-dropped chunk is exactly how a render-comparison tool reports "no differences" on a document it never actually read.

19. **Renders-correctly, API-accepts-it, and behaves-correctly are three DIFFERENT properties, and passing the first two proves nothing about the third — for any chart change that creates custom resources or reconfigures controller/GitOps behavior, offline render-level proof is not sufficient.** A shape that passes both `helm template` and `helm lint` (both entirely client-side) can still be REJECTED server-side because the live API enforces structural requirements the client-side tools never check (e.g. a field group requiring two sibling fields together that the client-side schema doesn't itself enforce). Same class: a GitOps-tool-specific diff-suppression setting can render correctly and still fail to actually suppress the diff once the tool applies with a stricter merge strategy — only a live patch-and-refresh proves it. Four-part guardrail: (1) pipe the rendered output into a server-side dry-run against a real (non-production) cluster, which catches schema-level rejections client-side tools cannot; (2) for any diff-suppression or sync-behavior change, verify it against a LIVE managed object (patch it, force a refresh, confirm it reports fully synced) before claiming it works; (3) at design time, read the target CRD's actual required-fields shape (not just its documentation) and dry-run a throwaway object before committing to a resource shape; (4) whenever a change swaps a pattern because of a deprecation warning, dry-run the replacement too — don't assume the replacement is automatically correct.

---
