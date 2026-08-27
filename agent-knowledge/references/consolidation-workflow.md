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
   f. **Deletion persists only when each `forget` is paired with an immediate export.**
      Symptom, if you get this wrong: consecutive forgets return rc=0 and print `Forgot [...]`
      while the corpus stays byte-for-byte identical. **The success message is emitted by the
      write, not by the persistence** — so rc=0 and `Forgot`/`Updated` are worth nothing here.
      Root cause: every `bd` invocation auto-imports `.beads/issues.jsonl` with UPSERT semantics
      (`bd import --help` says so outright). Upsert never deletes, so **any `bd` call between the
      forget and the next export — including a read like `bd memories` — re-imports the stale
      file and resurrects the record.** An early diagnosis of "verify it stuck" failed for
      exactly this reason: *the verification read was the bug.*
      **Working pattern — a loop of PAIRS, nothing in between:**
      `while read k; do bd forget "$k" && bd export --all -o "$ABS_JSONL"; done`.
      Never `forget k1 && forget k2 && export`. Batch-verify at the END, never between a forget
      and its export, and verify by re-reading in a FRESH process rather than by exit code.
      **Batching is safe only on a memory-empty export file — decide by measuring, never by
      assuming.** The import can only resurrect a record the file actually contains, so if
      `grep -c '"memory"' .beads/issues.jsonl` is 0 (which is what a previous plain `bd export`
      leaves behind — see the export gotcha in step 11), a whole batch followed by one export
      is correct and much cheaper. **After a correct `bd export --all` the file carries memories
      again, and the next batch is back under the pairing rule.** Check the count before choosing.
      **Cost and timeouts:** each call re-imports the whole file, so per-key cost grows with the
      store — run large batches detached, have the job write its own end marker, and block on the
      marker rather than inferring completion from a process check plus a log tail. After an
      interrupted batch, recompute the remainder as `forget-list ∩ live-keys` (re-derived from the
      store), not by line offset in the log.
      **If it still does not persist once correctly paired, STOP and report — never edit
      `.beads/issues.jsonl` directly.** That would be a tooling defect worth an upstream issue,
      not a licence to hand-edit the backing store. Editing the persistence layer because the API
      looks broken is a decision for the human: if the diagnosis is wrong, a backup is the only
      thing between them and silent loss of a cross-session knowledge store. Report the symptom,
      the evidence, and stop.

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
12. **Verify the export AFTER the final write, not after the first.** `bd export` without `--all`
    writes an issues-only `issues.jsonl`, silently dropping every memory from the portable
    artifact while the live store stays intact. Observed twice: the second time, a run's own
    verified "export retained N memories" did not hold minutes later, because a subsequent plain
    `bd export` had rewritten the file to issues-only. Nothing is lost while the store is
    authoritative, but **a cold start rebuilds from that file and would restore an empty hive.**
    Final assertion, after every writer has finished — **parse, never grep**:

    ```sh
    python3 -c "import json;print(sum(1 for l in open('.beads/issues.jsonl') if l.strip() and json.loads(l).get('_type')!='issue'))"
    ```

    Must be non-zero. An `awk`/`grep` line filter counts **blank lines** as memories — one issue
    plus two stray newlines reports 2 against a true count of 0 — so it returns a reassuring
    non-zero for exactly the issues-only file this assertion exists to reject. If the command
    raises instead of printing, the file is malformed: that is *could not measure*, which must
    never collapse to "zero".

    **The fix is not a single command.** `bd export --all -o .beads/issues.jsonl` writes the full
    file and `bd`'s own default-path auto-export then rewrites it issues-only within the same
    second. Export to a **scratch** path, verify it by parsing, `cp` it over
    `.beads/issues.jsonl`, verify again, and **run no further `bd` command** — a read-only
    `bd memories --json` has been enough to re-break it.

Classification guidance:
- Completed project summaries ("COMPLETE", "all PRs merged", batch records) -> STALE
- Superseded health/status runs (older run when newer exists) -> STALE
- PR review records (specific PR approval/feedback) -> STALE
- Session/compaction checkpoints -> STALE
- Per-instance records covered by a generalized pattern in learnings -> STALE **only with the `#N` citation from step 2b**
- Tool gotchas, Helm pitfalls, deployment patterns, troubleshooting insights -> REUSABLE
- Active project status, ongoing rollout tracking, user preferences -> ACTIVE

**A run record carrying a source-level claim is a finding wearing a run record's clothes — REUSABLE, not STALE.** If the body cites `file:line` in third-party source, names an upstream issue/PR number, or asserts version-specific behavior ("verified identical at X and Y and master"), the surrounding run is stale but the claim is not. Promote the claim, discard the run. This exact case cost us on 2026-07-31: two verified upstream defects (a dead Helm value from an env-name typo, and a type-only plugin comparison) were classified STALE with a batch of validation-run records and forgotten. They survived only because raw run logs elsewhere on disk happened to contain the memory text verbatim — nothing in the process guaranteed it, and they are now entries in the matching domain learnings file.

**Never batch-discard on category NAME — grade the state, not the namespace.** One pass correctly KEPT six records under a `validation/` prefix whose campaign was still in flight while staling thirteen records under a `baseline/` prefix from a campaign that had closed. Same shape of prefix, opposite verdicts. A key prefix is a filing decision made months earlier; it is not evidence about whether the work is live. Where a record's status is genuinely uncertain, **grep live repo or cluster state before classifying it** — two "fix it later" records were settled with one grep each, and one of them turned out to describe a defect that was still live rather than resolved.

**Assert the partition in code before writing anything.** Build the classification map programmatically and assert that `union(promoted-source-keys, stale, keep)` equals the input list exactly — no duplicates, no gaps. Every pass that did this caught a real error, including a hand count off by one across 145 keys. Apply the same rule to the coverage claims: re-derive that the proposed entry ids match the claimed ids, and resolve every asserted `learnings-<file>.md#<N>` against the live file rather than trusting the string.

**Generate discard-log bodies from a machine-readable dump, then assert each written body substring-matches its source.** Retyping is where truncation enters, and the loss is irreversible because there is no history to recover from. Note that `bd memories --json` prefixes two auto-import lines that break `jq` — strip them with `tail -n +3` or use a tolerant parser.

**Ratio sanity check.** When the pass ends with far more deletions than promotions, that alone is not alarming — dense merges are correct, and N per-cluster observations of one lesson *should* collapse to one entry. But spot-check the STALE bucket **before** running the batch, not after: the promoted items are verifiable afterwards, the discarded ones are not.

Verify by: No duplicate entries in learnings files. All promoted items are generalized (not project-specific). index.md is current. Cross-refs column in index.md matches actual `See also:` headers in each file. **Every deleted STALE record appears in the discard log** — its line count must equal M from step 11. **Spot-check 10 random promotions by quoting the destination line**, and confirm no learnings file lost content (diff against a pre-run snapshot; the only non-append edits should be entries you deliberately annotated).
```
