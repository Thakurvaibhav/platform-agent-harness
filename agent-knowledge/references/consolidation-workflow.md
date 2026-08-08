# Consolidation Workflow

Dispatched to `general-engineer` when the user approves `/consolidate`.

```
Goal: Consolidate bd memories into learnings files and clean up stale memories.

Note: Most reusable insights should already be in learnings files via immediate ingest (Completion Gate). Consolidation catches stragglers, enforces lint, and cleans stale memories.

Steps:
1. Run `bd memories` to list all memories.
2. For EVERY memory (regardless of prefix -- `<repo>/`, `<platform>/`, `<service>/`, etc.):
   a. Classify as: REUSABLE LEARNING (generalized pattern/gotcha/decision), ACTIVE STATE (ongoing project status), or STALE RECORD (completed project, superseded health run, historical PR record).
   b. If REUSABLE LEARNING: check if the insight already exists in a matching learnings file (use index.md keywords to find the right file). If not present, generalize the insight and append as a numbered item with `(ref: #NNN)` provenance when the memory references a PR/URL. **Write the learnings entry, then grep the destination file to confirm it landed, and only THEN `bd forget`.** Never delete on the strength of intending to write.
      **"Already covered" requires a citation, not a feeling** — name the `learnings-<file>.md#<N>` you are relying on. A 2026-07-26 pass judged 35 memories "already generalized" and proposed deleting them; an audit found only 6 were genuinely covered and 21 existed nowhere but bd. Those 16 `<repo>/methodology/*` memories had generalized bd→bd, so nothing ever reached a learnings file.
   c. If ACTIVE STATE: keep the memory (skip).
   d. If STALE RECORD: **append its full text to the discard log (step 2e) first**, then delete with `bd forget`.
   f. **If `bd forget` does not persist, STOP and report — never edit `.beads/issues.jsonl` directly.**
      Symptom seen 2026-08-06: 69 consecutive forgets returned rc=0 and printed `Forgot [...]`
      while the corpus stayed byte-for-byte identical. That is a tooling defect worth an upstream
      issue, not a licence to hand-edit the backing store. Editing the persistence layer because
      the API looks broken is a decision for the human: if the diagnosis is wrong, a backup is the
      only thing between them and silent loss of a cross-session knowledge store. Report the
      symptom, the evidence, and stop.

   e. **Discard log — mandatory, before any `bd forget` of a STALE record.** Append the complete key + body to `agent-knowledge/metrics/discard-<YYYY-MM-DD>.md`. `bd` exposes **no history** (`bd dolt` is server-lifecycle only — no `log`/`history` subcommand), so a forget is irreversible and the STALE bucket is otherwise unauditable by construction: once gone you cannot inspect what you discarded to judge whether it deserved it. The log makes an irreversible judgment reviewable. Report its path in your summary.
3. Memories already promoted to learnings files (duplicate content) should be deleted.
4. Check learnings files to see if any learnings need to be updated due to new info.
5. Check learnings files to see if any learnings need to be deprecated because they were incorrect.
6. **Cross-link lint**: For each learnings file, verify its `See also:` header matches the Cross-refs column in index.md. For entries mentioning keywords from another file's domain (check index.md Keywords column), add missing `See also:` pointers. Fix any broken references to renamed/removed files. **Reciprocal-link guard (run LAST, after every promotion):** a `See also:` link is a two-way edge. If you add `A -> B`, add `B -> A` in the same pass. Creating a new `learnings-*.md` means adding a back-link in every file it points at. Ten asymmetries shipped from one run on 2026-08-08 because this ran before the new files existed — re-run it at the very end. Verify with `drift-check.sh`; it must report zero cross-ref warnings before you finish.

**Header-presence guard**: verify EVERY `learnings-*.md` has a `See also:` header line near the top (not only inline/prose refs) — flag and add one if missing. (learnings-<domain>.md was prose-only until 2026-07-04; it may keep its richer "Detailed pointers:" prose block below the `See also:` line, but the line itself must be present for tooling/discovery.)
7. **Usage signal — READ-FREQUENCY, for ranking & gap-detection ONLY (NEVER pruning)**: Read `agent-knowledge/metrics/learning-reads.json` (per-file read counts, written automatically by the learning-gate hook on every `learnings-*.md` Read + `knowledge-search.sh` consult). **As of 2026-06-26 this REPLACES citation counts as the primary usage signal** — reads are a far truer proxy: agents read learnings files constantly but type a `#N` citation almost never (the citation experiment yielded only ~6 cited entries in 2 weeks of heavy work). `learning-usage.json`/`learning-citations.jsonl` (citations) remain as passive secondary telemetry only. This is platform/infra, where **recall ≫ precision**:
   - **NEVER archive or delete a learning for low/zero reads. Read frequency ≠ value** — a rarely-read file may hold the once-a-year gotcha that prevents a production incident.
   - RANK, not cull: report the most-read learnings files; optionally stamp the hottest file's key entries with `(validated: <today's date>)`. Read-frequency is per-FILE (you Read a file, not an entry), so ranking is at file granularity.
   - GAP-DETECTION (the higher-value use): cross-reference read-frequency against where work is actually happening (recent bd memories/PRs by domain). A domain with active work but a rarely/never-read learnings file signals a **discoverability or coverage gap** — flag "needs a learning" or "file not being found," never auto-remove. Also compare total reads vs `knowledge-search.sh` consults to gauge whether agents are searching the layer at all.
   - Report the top 5 most-read files and any flagged gaps. Learnings are removed ONLY when incorrect or superseded (step 5), never by usage.
   - **NOTE (experiment):** read-frequency tracking started 2026-06-26. Revisit in a few weeks to judge whether it earns its keep — citations did not.
8. **Keep the hive lean by PROMOTION, not deletion** (this is what keeps every subagent's `bd prime --memories-only` small): aggressively promote reusable bd memories into `learnings-*.md` (step 2b) so durable knowledge lives in the searchable learnings layer and bd holds only active/high-signal memories. Separately, `session/pre-compact-*` (session-scoped checkpoints, one per session id), legacy `session/pre-compact`/`k8s/pre-compact`, and `session/adhoc` memories older than 7 days are short-term continuity only — `bd forget` those. Goal: a small, high-signal persistent-memory set so priming stays cheap without losing recall.
9. **New file threshold**: If 3+ memories share a domain keyword not covered by any existing learnings file, create a new `learnings-<topic>.md` with those entries and add it to index.md.
10. Update index.md if any new topic directories or learnings files were created.
11. Run: bd remember "last consolidation: <today's date>, promoted N memories to learnings, deleted M stale/session records (discard log: <path>). N persistent memories remaining." --key <repo>/meta/last-consolidation

Classification guidance:
- Completed project summaries ("COMPLETE", "all PRs merged", batch records) -> STALE
- Superseded health/status runs (older run when newer exists) -> STALE
- PR review records (specific PR approval/feedback) -> STALE
- Session/compaction checkpoints -> STALE
- Per-instance records covered by a generalized pattern in learnings -> STALE **only with the `#N` citation from step 2b**
- Tool gotchas, Helm pitfalls, deployment patterns, troubleshooting insights -> REUSABLE
- Active project status, ongoing rollout tracking, user preferences -> ACTIVE

**A run record carrying a source-level claim is a finding wearing a run record's clothes — REUSABLE, not STALE.** If the body cites `file:line` in third-party source, names an upstream issue/PR number, or asserts version-specific behavior ("verified identical at X and Y and master"), the surrounding run is stale but the claim is not. Promote the claim, discard the run. This exact case cost us on 2026-07-31: two verified upstream defects (a dead Helm value from an env-name typo, and a type-only plugin comparison) were classified STALE with a batch of validation-run records and forgotten. They survived only because raw run logs elsewhere on disk happened to contain the memory text verbatim — nothing in the process guaranteed it, and they are now `learnings-<domain>.md#139/#140`.

**Ratio sanity check.** When the pass ends with far more deletions than promotions, that alone is not alarming — dense merges are correct, and N per-cluster observations of one lesson *should* collapse to one entry. But spot-check the STALE bucket **before** running the batch, not after: the promoted items are verifiable afterwards, the discarded ones are not.

Verify by: No duplicate entries in learnings files. All promoted items are generalized (not project-specific). index.md is current. Cross-refs column in index.md matches actual `See also:` headers in each file. **Every deleted STALE record appears in the discard log** — its line count must equal M from step 11. **Spot-check 10 random promotions by quoting the destination line**, and confirm no learnings file lost content (diff against a pre-run snapshot; the only non-append edits should be entries you deliberately annotated).
```
