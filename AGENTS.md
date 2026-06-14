# AGENTS.md — about this repository

This repository **is** the `platform-agent-harness`. It is the source of the harness itself — not an infra or platform repo. The file you are reading exists so any CLI agent opened in this directory knows how to behave.

## If you are adopting the harness

The instruction contract you copy into **your** infra repo lives at [`templates/AGENTS.template.md`](templates/AGENTS.template.md). Copy that file to your repo as `AGENTS.md`, then pick a runtime wiring from [`adapters/`](adapters/). The end-to-end story is in [`README.md`](README.md) and the compaction lifecycle is in [`LIFECYCLE.md`](LIFECYCLE.md).

**Do not copy this file.** It only describes the harness source repo itself.

## If you are working inside this repo

- Keep all content public-safe. No real cluster names, account IDs, customer names, internal URLs, or tokens.
- Before every commit that touches examples, references, or templates, run [`sanitization/prepublish-checklist.md`](sanitization/prepublish-checklist.md) (`trufflehog`, `gitleaks`, the local denylist).
- Search [`agent-knowledge/references/index.md`](agent-knowledge/references/index.md) before adding new docs — reuse before duplication.
- Runtime-specific assumptions belong only under [`adapters/`](adapters/). `core/`, `skills/`, and `domain-packs/` must stay portable.
- Match the tone and structure of the closest existing files when editing.

## Safety defaults that apply here too

- No mutating Kubernetes commands.
- No pushes to `main` / `master`. No force-pushes to protected branches.
- Never delete or overwrite untracked files without explicit instruction — treat them as user-owned work.
- No real `graphify-out/`, `.beads/`, runtime settings, MCP credentials, sessions, or logs in commits.
