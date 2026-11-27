# `agent-knowledge/`: the knowledge layer

An offline knowledge base that coding agents read before they grep a repo. It
holds what you already learned the hard way, so the next agent does not re-derive
it, and answers from local files with no network call and no embedding service.
Two tiers, and the split is the whole design:

- **`references/`**: the **portable** tier. Method, protocol, and vendor
  behaviour that stays true when you change employer.
- **`orgs/<org>/`**: the **instance** tier. Cluster names, account IDs, fleet
  inventories. True of one estate and nowhere else.

**What it is not.** Not a vector database, not a RAG service, not a wiki for
humans. Entries are written to be *cited* mid-task, which is why a result is
`learnings-istio.md#59` rather than a file to go read. This directory works on
its own; the rest of the repo (agents, hooks, skills) is optional.

## Dependencies

| What | Why |
| --- | --- |
| [`bd`](https://github.com/steveyegge/beads) | **Hard dependency.** The hive: the fast write path for a learning you hit mid-task, and one of the surfaces searched. `learn.sh` wraps `bd remember`, and nothing degrades gracefully without it (see Known limits). |
| `python3` | Ranking. `bm25-search.py` scores entries; `drift-check.sh` is a Python program that kept its `.sh` name. **3.9+**, standard library only. |
| `ripgrep` (`rg`) | The fallback backend (`SEARCH_BACKEND=ripgrep`), and the text match over files with no citable entries. Any recent version. |

`git` is needed only for the drift check's graph-staleness warnings.

## Install and configure

Put this directory anywhere: the scripts resolve the home **relative to
themselves** first, so a checkout in any location searches itself unconfigured.
Estate paths live in `config.sh`, never in a script. `env.sh` ships generic
defaults only, and `config.sh` is gitignored so a public checkout never carries
one org's paths.

```sh
cp -r agent-knowledge "$HOME/.agent-knowledge"
cp config.template "$HOME/.agent-knowledge/config.sh"   # then edit it
echo '. "$HOME/.agent-knowledge/env.sh"' >> ~/.zshrc
```

Check what resolved, and from where, so a wrong value is visible not silent:

```console
$ ~/.agent-knowledge/env.sh --config
config file: /home/you/.agent-knowledge/config.sh (present)

  HARNESS_HOME       pre-config   /home/you/.agent-knowledge
  WORK_ROOT          config       /home/you/src
  BEADS_DB           default      /home/you/src/.beads
  ACTIVE_ORG         config       example

precedence: environment > config.sh > generic default
```

`ACTIVE_ORG` labels where new writes go. **It must never narrow a read**: every
org is searched unconditionally, which is the point of carrying the knowledge at
all. See [`core/protocols/knowledge-tiers.md`](../core/protocols/knowledge-tiers.md).

## The three things you actually do

### 1. Capture, the moment you hit something

Batching to the end of a task is why learnings get lost.

```console
$ scripts/learn.sh "Argo CD registers the Helm dependency repos named in Chart.yaml BEFORE helm dependency build" k8s/lesson/argocd-dep-repos
Remembered [k8s/lesson/argocd-dep-repos]: Argo CD registers the Helm dependency repos ...
```

It walks up to the nearest `.beads`, falling back to `$BEADS_DB`. Omit the key
and `bd` derives one. The bar is durable and reusable, not a restatement of what
you just did.

### 2. Search, before you implement

```console
$ scripts/knowledge-search.sh helm chart dependency version
## Knowledge Search: helm chart dependency version

### index.md (curated router — start here)

index rows matching the MOST query terms — the curated answer:
  3/4 terms  agent-knowledge/references/learnings-helm-ci.md

### entries, BM25-ranked (both tiers — the citation is the result)

learnings-helm-ci.md#75    **After bumping a chart's own `version` or a dependency ...
learnings-argocd.md#93     **Argo CD registers the Helm dependency repos named in ...
```

Then reading notes, domain docs, and the bd hive last, it being the biggest and
least routed surface. The citation is the result: quote `learnings-helm-ci.md#75`
and build on it rather than re-deriving.

When the corpus holds no answer, the entries section says so in place of the rows
(`no close match for '<query>' (best covers 22%) ... treat this as a gap in the
corpus`) rather than presenting near-misses as an answer. With `--quiet-weak` it
prints **nothing at all**: for a hook, or any caller that did not ask a question,
a low-confidence guess is noise that teaches agents to skip this layer.

### 3. Consolidate, periodically

Memories are the fast write path; `learnings-*.md` are the curated read path.
Consolidation promotes one to the other: dedupe, merge, file into the right topic
file, record the date. **It is ask-first and manual.** There is no scheduled
runner, deliberately: an automatic pass that silently rewrites the corpus is not
something you want to discover after the fact. Workflow:
[`references/consolidation-workflow.md`](references/consolidation-workflow.md).

`drift-check.sh` says when it is due, plus index gaps and dead cross-references:

```console
$ scripts/drift-check.sh
## Harness Drift Warnings (2)

- DRIFT: Last consolidation was 11d ago (2026-11-16). Consider /consolidate
- DRIFT: learnings-uv.md exists but is not indexed in index.md (discovery gap)
```

Exit `0` clean, `1` warnings (non-blocking).

## How ranking works

Three layers, cheapest first.

**A curated keyword router.** `references/index.md` carries a hand-maintained
Keywords column per file, and the search leads with it, ranking rows by how many
**distinct** query terms they match. A raw body grep bypasses exactly this: an
intent hook like "pod debugging" routes well but appears nowhere in the prose. If
a body match is relevant and no index row matched, add the missing keywords.

**Entry-level BM25.** `bm25-search.py` scores one numbered entry, not one file,
with IDF and length normalisation, because the raw match count the ripgrep path
uses has neither and lets the largest files win queries they have nothing to do
with. Tokenisation splits hyphens, underscores and camelCase, so
`PeerAuthentication` and `peer-authentication` reach the same entry; closed-class
stopwords are dropped, entries being full sentences.

**A weak-result verdict.** The ranker also reports *coverage*: how much of the
query, weighted by IDF, the top hit contains. Below `BM25_COVERAGE_FLOOR`
(default `0.40`) the result is labelled a gap. The floor is calibrated, not
borrowed: at 0.50 it began suppressing queries whose top hit *was* the answer.

## Known limits

- **`bd` is a hard dependency.** Without it the hive section degrades to "(bd
  memories unavailable)", but `learn.sh` has nowhere to write at all. There is no
  file-only capture path yet.
- **Coverage judges the TOP hit only.** A query answered jointly by three
  mid-ranked entries, none complete on its own, can still be labelled weak.
- **The two-tier split is a convention the tooling does not enforce.** Nothing
  stops you writing a cluster name into `references/`. What catches it is
  [`sanitization/prepublish-checklist.md`](../sanitization/prepublish-checklist.md),
  run before publishing, not the search.
- **Ranking is lexical.** No synonyms, no embeddings: a query sharing no
  vocabulary with an entry will not find it. Compensating for that is most of
  why the curated router exists.

## The rest of the tree

[`reading/`](reading/) is external reading notes, a **separate trust tier**:
curated, not yet proven in your stack. [`metrics/`](metrics/) is usage telemetry,
driving consolidation ranking and gap detection and **never pruning**. **Edit
canonical files here; never copy them into a runtime-specific directory**, since
a runtime points *at* this home rather than owning a copy. Wiring:
[`adapters/`](../adapters/), [`installation/`](../installation/).
