# Pre-Publish Sanitization Checklist

Run this gate before every commit that touches `examples/`, `references/`, `templates/`, agent prompts, or any other public-facing harness file.

## Tools

| Tool | Purpose |
| --- | --- |
| [`trufflehog`](https://github.com/trufflesecurity/trufflehog) | Verified-secret scanner with broad detector coverage. |
| [`gitleaks`](https://github.com/gitleaks/gitleaks) | Fast regex-driven secret scanner. Catches what trufflehog's verifiers miss. |
| `rg` (ripgrep) | Used to match the local redaction denylist. |
| `python3` | Runs the format and path validators below. |

## Sequence

```bash
ROOT=$(pwd)

# 1. Verified-secret scan
trufflehog filesystem "$ROOT" --no-update --fail

# 2. Pattern-based secret scan
gitleaks detect --no-git --redact --verbose --source "$ROOT"

# 3. Local denylist (your real cluster names, ticket prefixes, domains)
test -f "$ROOT/.redaction-denylist" && rg -nFf "$ROOT/.redaction-denylist" "$ROOT" --glob '!__pycache__' --glob '!.git' || echo "no local denylist"

# 4. Formatting (whitespace, trailing newlines)
python3 sanitization/check-format.py "$ROOT"

# 5. Index integrity (every path in references/index.md exists)
python3 sanitization/check-index.py "$ROOT"

# 6. Diff hygiene
git diff --check
```

Any non-empty output from steps 1–3 or non-zero exit from steps 4–6 is a **blocking** finding.

## Bootstrap the local denylist

```bash
cp templates/redaction-denylist.template.txt "$ROOT/.redaction-denylist"
# populate with YOUR real cluster names, customer names, internal domains, ticket prefixes
```

The denylist file itself is git-ignored (see `.gitignore`).

## What ships, what does not

**Ships:**

- Public open-source tool names (`tetragon`, `kyverno`, `infisical`, `istio`, `otel`, `cert-manager`, `external-dns`, `envoy-gateway`).
- Placeholder cluster names (`<cluster>`, `<env-cluster>`, generic `dev-01` / `stag-01` / `prod-01` style names from public reference architectures).
- Generic ticket / repo placeholders (`<TICKET-KEY>`, `<repo>`, `<service>`).
- Public upstream URLs (GitHub repos, Helm chart repos, documentation sites).

**Does not ship:**

- Real cluster identifiers, customer-tenant names, account/project IDs.
- Real ticket prefixes (jira `ID-`, etc.) or ticket numbers from real systems.
- Real datasource UIDs, dashboard URLs, stack URLs, on-call schedules.
- Real internal domains, VPN endpoints, internal wiki URLs.
- Real secret-shaped tokens (`glsa_`, `ghp_`, `github_pat_`, etc.).
- `graphify-out/` from a real private repo.
- `.beads/` from a real session.
- Runtime sessions, history, logs, MCP config, auth files.

## Sample local denylist row

```
# .redaction-denylist (NOT committed)
my-real-cluster-prod-01
acme-customer-tenant
internal.example.com
PROJ-
glsa_
ghp_
```

## When sanitization finds something

1. Replace the offending string with a synthetic placeholder.
2. If the original was intentional context, move it to your local notes (outside the repo).
3. Re-run the full checklist.
4. Do not push until all six steps are clean.
