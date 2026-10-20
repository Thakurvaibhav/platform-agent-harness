# Evidence

The README quotes a few headline numbers. This page is the other half: a sample of the
corpus those numbers come from, so you can judge the source rather than take the claims.

Every item below is a real entry in [`agent-knowledge/references/`](../agent-knowledge/references/),
quoted as it appears there, with its citation key. The corpus is **1,766 numbered entries across
25 files**. Nothing here was written for this page.

Instance details — cluster names, project ids, service names — are genericized to
`<placeholders>` on the way out of the private harness this is derived from. The measurements are not.

---

### A hard-coded diff base produces a gate whose failure mode is a PASS
`learnings-code-review.md#108`

> Two active repos here default to **different** branches (`dev` and `main`). Measured cost of
> getting it wrong on the `dev`-default repo: the correct base gave **11 files / 92 insertions**;
> hard-coded `origin/main` gave **80 files / 4,392 insertions** — […] which is how a discipline
> gate invents findings in files the PR never touched.

This is why every gate and worktree recipe in the harness resolves the base ref from
`origin/HEAD` instead of assuming `main`.

### An unanchored email regex in a logging filter is an unauthenticated ReDoS
`learnings-code-review.md#121`

> measured **11.9 ms at 2 KB, 195 ms at 8 KB, 790 ms at 16 KB, 3.13 s at 32 KB** (4× per doubling)
> — all synchronous inside a logging filter on the access line, so it blocks the event loop for
> unrelated requests and **needs no authentication**.

### Recompressing image layers gzip → zstd buys a third of the quoted number
`learnings-container-images.md#8`

> Measured on five SHA256-verified real layers: **1,582.9 MB gzip → 1,482.6 MB zstd-3, a 6.34 %
> saving**, not the 10-20 % commonly quoted […] note that a version census proves only the decoder
> floor: no image has actually been deployed.

### A warm pool is sized by arrival rate × refill time, not by concurrency
`learnings-agent-sandbox.md#64`

> `spec.replicas` counts **idle** warm pods, but the common formula sizes it to a multiple of the
> EMA of concurrent in-use claims. Measured on a real pool: 154 active long-lived claims against 40
> warm wanted 185 (clamped), while the actual need was set by how many new claims arrive inside one
> refill window.

### Grading a latency change on sampled events gets it wrong in both directions
`learnings-code-review.md#51`

> the correctness lens was wrong twice before measurement settled it […] **n=400 for the exact
> production image was strictly BIMODAL: median 0.358 s, p75 0.436 s, then p90 97.7 s**

### Most quoted agent A/B results are below the measurement floor
`learnings-agent-workflow.md#279`

> ~253 paired examples for 80 % power on a 5 pp effect (one-sided, α .05); 50 examples ≈ **35 %**
> power, 100 ≈ **51 %** […] **Treat any sub-10 pp harness claim at N<100 as unmeasurable and say so.**

Including the ones on this project's own README. They are reported as measured, not as proven.

### `rtk` silently truncates `gh pr diff`, so the harness forbids that one pairing
[`core/protocols/rtk-command-policy.md`](../core/protocols/rtk-command-policy.md)

> measured on a 9-file PR it emitted 7 files and 25 hunks against the raw 18 diff markers and 32
> hunks, dropping two files outright and 26 additions inside another.

A reviewer working from the truncated diff silently skips whole files — which is why the token-
optimization policy is an allowlist with a named exception, not "wrap everything read-only."

### Two gates in this repo were checking nothing

A health-check function was defined and never called, so every "all clear" it printed was silent
about the thing it claimed to cover. A comment-policy gate only inspected lines *starting* with a
comment token, so the rule it enforced was avoidable by moving the comment inline. Both shipped in
this repository, were found by audit, and are fixed in
[`agent-knowledge/scripts/drift-check.sh`](../agent-knowledge/scripts/drift-check.sh) and
[`core/hooks/generic/comment-discipline.sh`](../core/hooks/generic/comment-discipline.sh) — and the
CI in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) now runs this repository's own gates
against itself on every pull request, which is the only reason to believe the next one is checking
anything.

---

## How the corpus works

Entries are numbered and append-only. Nothing is deleted: a duplicate is merged into the lower
number leaving a `MERGED into #N` marker, and a corrected entry is marked `SUPERSEDED by #N` with
its original body intact — because entries are cited as `[file.md#N]` from other files and from
agent memory, and a deletion breaks those references silently.

Knowledge is two-tier. Portable method and vendor behaviour live in
[`agent-knowledge/references/`](../agent-knowledge/references/); anything true of only one estate
lives in a per-org tier that does not ship. The discriminator is in
[`core/protocols/knowledge-tiers.md`](../core/protocols/knowledge-tiers.md).
