# `orgs/` — the instance knowledge tier

One directory per employer, client, or estate. Everything in here is true of **one** environment and nowhere else: cluster registries, account IDs, fleet inventories, metric allowlists, alert routes, team and identity tables, per-service onboarding state.

The portable half of the corpus — method, protocol, and third-party behavior that travels — lives in [`../references/`](../references/). Which tier a given fact belongs to is decided by the payload/locator rule in [`core/protocols/knowledge-tiers.md`](../../core/protocols/knowledge-tiers.md), the canonical spec for everything on this page.

## Layout

```
agent-knowledge/
├── references/            # portable: learnings-*.md, protocols, tool guides
│   ├── learnings-istio.md
│   └── learnings-observability.md
└── orgs/
    ├── acme/              # ACTIVE_ORG=acme
    │   ├── clusters.md    # the cluster registry — usually the first file
    │   ├── istio.md
    │   └── observability.md
    └── <previous-org>/    # kept, still searched, no longer written to
        └── clusters.md
```

## Rules

| Rule | Why |
| --- | --- |
| **No basename may collide with a file in `references/`** | `orgs/acme/learnings-istio.md` beside `references/learnings-istio.md` makes every `learnings-istio.md#12` citation ambiguous, and the usage counter in [`../metrics/`](../metrics/) is keyed on basename, so the two series merge into one meaningless number. Drop the `learnings-` prefix here; the path carries the scope. |
| **Cite as a path, not a bare basename** | `orgs/acme/istio.md#4`, never `istio.md#4`. |
| **Never delete a previous org's directory** | It is precedent. `knowledge-search.sh` still searches it; `ACTIVE_ORG` only stops new writes from landing there. |
| **Absence claims live here, always** | "Metric `X` does not exist" is a fact about one allowlist. In `references/` it is not stale, it is wrong — and wrong in the direction that stops the next agent from looking. |
| **Numbered, append-only, self-contained** | Same entry discipline as `references/learnings-*.md` (see [`../references/README.md`](../references/README.md)). |

## How search treats this tier

[`../scripts/knowledge-search.sh`](../scripts/knowledge-search.sh) emits one labelled section per org, unconditionally, with the active one marked:

```
### learnings (project)
### org: acme (instance knowledge — ACTIVE)
### org: <previous-org> (instance knowledge)
### reading (external notes)
```

`ACTIVE_ORG` is a label on that output, not a filter over it. If a search surface ever starts restricting to the active org, previous-estate knowledge disappears without any error — the results still look complete. That invariant is stated in `env.sh` and enforced in the script.

An empty or missing `orgs/` degrades gracefully: the section prints a "no org knowledge yet" line and the script still exits 0.

## Seeding a new org

```sh
mkdir -p "$HARNESS_HOME/orgs/<org>"
# then set ACTIVE_ORG=<org> in env.sh and start with clusters.md
```

The full runbook — with the checks that catch a tier that exists but is not searchable — is [`installation/new-org-setup.md`](../../installation/new-org-setup.md).

A `clusters.md` worth having answers, per cluster: **name · tier · cloud/provider · owning team · kube context · delivery mode** (tracks main vs pinned), plus an explicit statement of which attributes the *name* does **not** encode. Cluster names that look like they encode an environment or a cloud, but do not, are a recurring source of expensive misroutes; say so at the top of the file rather than letting each agent re-infer it.

## Publishing note

This directory ships with **only this README**. Real org content is instance knowledge by definition — it belongs in the deployed home (`$HARNESS_HOME/orgs/<org>/`), never in a public harness repo. Anything committed here must pass [`sanitization/prepublish-checklist.md`](../../sanitization/prepublish-checklist.md), which for this tier effectively means: do not commit it.
