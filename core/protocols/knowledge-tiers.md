# Knowledge Tiers — Portable vs Instance

Every agent harness that lives longer than one job accumulates two kinds of knowledge, and they have opposite lifetimes. This protocol keeps them in separate directories so one can be carried and the other can be dropped.

| Tier | Path | Holds | Lifetime |
| --- | --- | --- | --- |
| **Portable** | [`agent-knowledge/references/`](../../agent-knowledge/references/) | Method, protocol, and third-party/vendor behavior that travels: how a controller reconciles, how a chart deep-merge resolves, how to run a fleet campaign, how to review a PR | Follows you across employers, machines, and clients |
| **Instance** | `agent-knowledge/orgs/<org>/` | Facts true only of one estate: cluster names and topology, account IDs, fleet inventories, metric allowlists, alert routes, team/identity registries, per-service tables | Dies with the estate. Kept, but never mistaken for method |

Both tiers are **read** on every task. Only the portable tier is **claimed** as generally true.

## The discriminating rule

Deciding which tier a given fact belongs to is the whole difficulty, and "is a cluster name mentioned?" is the wrong test. Use this instead:

- **Payload → instance.** If the separable content of the entry *is* the estate data — a census, a per-cluster table, a metric inventory, an alert-route map, an identity registry, a list of which services are onboarded — it belongs in `orgs/<org>/`. Strip the data and nothing generalizable is left.
- **Locator → portable.** If a path, chart name, PR number, or a cluster is named as the *site of proof* for a general claim, the entry stays in `references/`. "Verified on `<cluster>`; the chart's `httpRoutes: null` deep-merge drops the parent list" is a portable lesson that happens to cite where it was proven. Removing the name does not weaken the claim; it only removes the receipt.

**Tie-breaker, when a case is genuinely ambiguous:** *would a reader at a different company act differently because of this?* If yes, it is portable. If it only tells them what your old estate looked like, it is instance.

### Corollary: absence claims are always instance-scoped

"Metric `X` does not exist," "there is no `Y` label," "that field is never populated" — these are facts about **one** allowlist, one scrape config, one deployment. They are not properties of the tool. Filed in `references/`, an absence claim is not merely stale at the next employer; it is **actively wrong**, and it is wrong in the direction that stops an agent from looking. Every absence claim goes in `orgs/<org>/`, or gets rewritten as a presence claim about your configuration ("our allowlist drops `X`; check yours before assuming it is absent").

## `ACTIVE_ORG` — labels writes, never narrows reads

`ACTIVE_ORG` (set in [`agent-knowledge/env.sh`](../../agent-knowledge/env.sh)) names the org whose tier is current. Its only jobs are:

1. deciding which `orgs/<org>/` directory **new writes** land in, and
2. deciding which org an agent names in prompts and reports.

**It must never be used to filter a search.** [`knowledge-search.sh`](../../agent-knowledge/scripts/knowledge-search.sh) searches **every** org directory unconditionally and labels the active one; it does not restrict to it. Knowledge from a previous employer stays findable as precedent — that is the entire point of keeping the tier rather than deleting it. An `ACTIVE_ORG` filter on the read path fails silently: results still arrive, they are still relevant-looking, and the corpus you no longer see is invisible precisely because you cannot see it.

If you add a new search surface (another backend, another index, another tool), the invariant is the thing to check first: does it enumerate all orgs, or only the active one?

### Before switching search backends — the `orgs` collection is not optional

The concrete case today is the `SEARCH_BACKEND=qmd` seam in [`knowledge-search.sh`](../../agent-knowledge/scripts/knowledge-search.sh). The default backend is ripgrep, which walks `orgs/*/` directly and so satisfies the invariant by construction. **The qmd path does not.** It issues a *single* search over qmd's configured collections, so it covers the instance tier only once an `orgs` collection has been added to qmd.

**Add that collection before flipping the backend.** Without it, org knowledge drops out of every result — and it drops out in exactly the way the invariant above warns about: no error, no empty section, no warning. Results still arrive, they still look complete, and the whole instance tier is missing from them. This is a one-word change that can silently remove a corpus from view, so treat it as a change to the read path rather than a performance tweak.

`bd memories` always use ripgrep regardless of `SEARCH_BACKEND`, so that surface is unaffected either way.

## Naming constraint — org files must not collide with `references/`

Org files **must not share a basename** with any file in `references/`.

`orgs/acme/learnings-istio.md` sitting beside `references/learnings-istio.md` makes every `learnings-istio.md#12` citation ambiguous — the reader cannot tell which corpus item 12 lives in, and neither can the next agent. It also breaks measurement: the usage counter in [`agent-knowledge/metrics/`](../../agent-knowledge/metrics/) is keyed on **basename**, so two files with one name merge into a single, meaningless series.

**Convention:** drop the `learnings-` prefix in the org tier and let the path carry the scope.

| Portable | Instance | Cite as |
| --- | --- | --- |
| `references/learnings-istio.md` | `orgs/acme/istio.md` | `learnings-istio.md#12` / `orgs/acme/istio.md#4` |
| `references/learnings-observability.md` | `orgs/acme/observability.md` | `learnings-observability.md#31` / `orgs/acme/observability.md#7` |

Cluster registries have no portable counterpart and follow the same rule by default: `orgs/<org>/clusters.md`.

## Tombstoning — moving an entry without breaking references

Numbered learnings are referenced by bare `#N` from bd memories, handoff reports, PR comments, other learnings files, and session transcripts you cannot rewrite. A corpus of any age carries hundreds of these, and no find-and-replace can locate them all.

So when an entry moves from `references/` to `orgs/<org>/`, **leave a one-line stub at the old number. Never renumber.**

```markdown
12. MOVED → `orgs/acme/istio.md#4` (instance knowledge: per-cluster revision inventory).
```

The stub costs one line and keeps every existing `#12` resolvable. Renumbering the file to close the gap saves nothing and silently redirects every old citation to the wrong entry — the failure mode is not a broken link, it is a confidently wrong one.

Same rule for the reverse direction and for splits: if an entry is partly method and partly payload, keep the method at the original number, move the payload to the org file, and cross-link both ways.

**Detecting mis-resolution, and the case this rule does not cover.** A confidently-wrong reference cannot be found by a dangling-reference scan — it resolves. Two things follow. First, when entries are copied between two corpora that number *independently* (porting from a private corpus to a public one, merging two knowledge bases), tombstoning does not help: every `#N` that lands in range now points at an unrelated entry. Strip or re-resolve each one at the boundary, by opening the target — a range check is not a resolution check. Second, run the detector **differentially**: capture its output before the change and diff. Absolute counts are dominated by pre-existing references and are not actionable; only the delta tells you what you broke. See `agent-knowledge/references/learnings-agent-workflow.md` → "Numbered-corpus hygiene" for the detection commands and the duplicate-number audit.

## How this composes with the other stores

The four-store routing table lives in [`bd-and-memory.md`](bd-and-memory.md) → "Memory routing". The tier split refines exactly one row of it: durable curated knowledge is not one bucket but two, and the payload/locator rule above decides which.

```
reusable engineering pattern ─────────────► references/learnings-*.md
fact about this estate only ──────────────► orgs/<ACTIVE_ORG>/<topic>.md
operational / still uncertain ────────────► bd remember
runtime-only config trivia ───────────────► the runtime's own memory
```

## Splitting an existing single-tier corpus

Doing this to a live corpus, in order:

1. **Create the tier.** `mkdir -p agent-knowledge/orgs/<org>/`, set `ACTIVE_ORG` in `env.sh`.
2. **Pass file by file, entry by entry.** Apply the payload/locator rule per numbered entry, not per file — most files are mixed.
3. **Move payload out, tombstone the old number.** Keep locator entries where they are.
4. **Rename on the way out** so no basename collides (`learnings-foo.md` → `orgs/<org>/foo.md`).
5. **Re-run the search** for a term you know is in the moved content, and confirm it still returns — from the org section this time. A move that drops out of search results is a move that deleted knowledge.

Step 5 is the one people skip. Do it with a term whose absence you would notice.
