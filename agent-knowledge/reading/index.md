# Reading Notes — external-source knowledge

Distilled, vetted notes from web articles / papers / talks. **Separate trust tier
from `references/learnings-*.md`** (project learnings = battle-tested fact; reading
notes = external, curated but not yet proven in your stack). Same md+frontmatter
conventions so all harnesses (Claude, Codex, Factory) and search read them.

**How notes get here:** the `/ingest-reading <url|file>` skill fetches → distills →
you vet interactively → it writes a note here and registers it below. Raw articles
are never dumped; only durable, synthesized takeaways + a "how this applies to us"
lens. This is the Karpathy LLM-wiki model (compile sources into durable pages), not RAG.

**Search:** `~/.agent-knowledge/scripts/knowledge-search.sh <terms>` covers this dir.

## Notes

| Note | Source | Tags | Applies to | Maturity |
|------|--------|------|-----------|----------|
| [ztunnel-long-straw-model](ztunnel-long-straw-model.md) | [jackma.com](https://jackma.com/2026/07/03/ztunnel-unmasked/) | istio, ambient, ztunnel, hbone, mtls, network-policy | istio, network-policy, k8s | reference |

---

## qmd flip (deferred — do NOT install yet)

Search runs on ripgrep today. When the corpus grows enough that keyword search gets
slow or misses semantically (rule of thumb: >~150 notes, or you're re-reading to find
things), flip to **qmd** — no migration, because notes are already qmd-shaped and qmd
indexes from files on demand.

Why deferred: qmd hard-depends on `node-llama-cpp` (heavy native model runtime) even
for keyword search — not worth the weight at low volume. There is NO early-adoption
benefit: a qmd "collection" is just a rebuildable index over these files, so adopting
later indexes the whole corpus identically.

**Flip steps (later):**
```sh
npm install -g @tobilu/qmd          # or bun
qmd collection add ~/.agent-knowledge/reading   --name reading
qmd collection add ~/.agent-knowledge/references --name learnings
qmd context add qmd://reading "External-source reading notes (curated, not yet proven in-stack)"
qmd embed                            # only if semantic (vsearch/query) needed
```
Then set `SEARCH_BACKEND=qmd` — `knowledge-search.sh` already routes to it when present.
