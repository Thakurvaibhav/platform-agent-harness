---
name: ingest-reading
description: |
  Ingest an external source (web URL or local file) into the reading-notes corpus
  at ~/.agent-knowledge/reading/. Use when the user shares an article/paper/talk to
  "add to learnings/reading", "save this for later", "ingest this url", "distill this
  into a note", or drops a file to capture. Fetches, distills into a durable vetted
  note (NOT a raw dump), gets the user's approval interactively, then writes it and
  registers it in the reading index. Do NOT use for project learnings (those go in
  references/learnings-*.md via consolidation) or for answering questions.
---

# Ingest Reading

Turn an external source into a durable, vetted reading note in the shared knowledge
base. Model: **Karpathy LLM-wiki** — compile the source into synthesized knowledge,
don't store raw text. The corpus is a **separate trust tier** from project learnings:
external, curated, not yet proven in your stack. Keep dirty/unvetted info out by
running the vet step interactively.

Corpus: `~/.agent-knowledge/reading/`  ·  template: `reading/_template.md`  ·  index: `reading/index.md`

## Steps

1. **Get the source.** URL → fetch (WebFetch, or `gh api` for GitHub). Local file → read it.
   If it's paywalled/JS-heavy and fetch is thin, tell the user and ask for a paste/PDF.

2. **Distill (do not dump).** Produce a *candidate* note using `reading/_template.md`:
   - `TL;DR` — the one durable idea.
   - `Key takeaways` — durable points, each usable without re-reading the source.
   - **`How this applies to us`** — your platform lens (k8s/istio/argocd/agents/etc.).
     If it doesn't apply directly, say so — "useful as background" is a valid outcome.
   - Frontmatter: `title, source_url, author, date_added` (today), `tags`, `maturity`
     (external-opinion | established-practice | reference), `applies_to`, `status: draft`.
   - Cross-links: grep `~/.agent-knowledge/references/learnings-*.md` (or run
     `knowledge-search.sh <topic>`) for related project learnings; list real `[[learnings-x]]` links.

3. **Vet interactively (the dirty-info guard).** Show the candidate note to the user.
   Ask them to approve / edit / cut sections / reject. Apply their edits. Do NOT write
   until they approve. If they reject, stop — nothing is written.

4. **Write.** Slug the title (`kebab-case`, dated if useful) → write to
   `~/.agent-knowledge/reading/<slug>.md`. Set `status: vetted`.

5. **Register.** Append a row to the `## Notes` table in `reading/index.md`
   (Note link · Source · Tags · Applies to · Maturity). Remove the placeholder row if present.

6. **Cross-link back (optional, if strong).** If the note materially informs a project
   learning, add a one-line pointer in that `learnings-*.md` (e.g. under a relevant entry:
   "See also reading/`<slug>.md`"). Keep it sparing — only genuine connections.

7. **Confirm.** Tell the user the path written + the takeaways captured. If the reading
   corpus is large and search felt slow, remind them the `qmd flip` is available (see
   `reading/index.md`).

## Rules
- Never write without the user's approval (step 3). Never dump raw article text — distill.
- One note per source. If re-ingesting an updated source, update the existing note in place.
- Reading notes are FILES, not bd memories. The hive stays operational; reading is durable prose.
- Notes live only in `~/.agent-knowledge/reading/` — do not touch `references/learnings-*.md`
  content except the optional one-line cross-link in step 6.
