# Seeding the harness at a new org — an agent runbook

**You are the agent, running on a machine where the harness is installed but pointed at the previous org.** Everyone who keeps an agent harness for more than a year eventually does this: new employer, new client, new laptop, same accumulated method. This runbook re-points the harness and verifies it landed, without discarding what travels.

It is written **for an agent to execute**, not for a human to skim. Every step carries the command, the concrete output that means success, what to do when the output is anything else, and what to ASK rather than guess. That shape is deliberate — a checklist of good intentions cannot tell you that a check passed for the wrong reason.

Scope: the knowledge tiers, the path switch, credentials, and placement verification. Moving files between machines (archives, restores, tool reinstalls) is out of scope — the *concepts* here apply to a machine move, the mechanics are yours.

**Three rules for this runbook:**

1. **Ask, do not guess.** §0 lists what you cannot infer. Get answers before you edit anything.
2. **Verify, do not assume.** Every step states the output that means success. If you see something else — *including silence* — treat it as failure and follow the "if it fails" line. The worst bugs in a harness are checks that report "all clear" because they were grepping for text the tool stopped printing.
3. **Report honestly at the end.** A precise list of what is still broken beats a green summary. Say which steps you could not verify, and why.

---

## §0. Ask the user first

Ask all of these in one message, with the defaults shown, and accept "use the default" for any of them. Do not edit `env.sh` without answers.

| # | Question | Default | Becomes |
| --- | --- | --- | --- |
| 1 | Short name for the new org (lowercase, no spaces) | — *(must be answered)* | `ACTIVE_ORG` |
| 2 | Where should repos and the bd hive live? | `$HOME/Work/git-repos` | `WORK_ROOT`, and `BEADS_DB="$WORK_ROOT/.beads"` |
| 3 | Where should domain docs live? | `$HOME/Work/docs` | `HARNESS_DOCS` |
| 4 | Issue tracker base URL | — *(ask; the `create-pr` skill builds ticket links from it)* | `JIRA_BASE_URL` |
| 5 | Which cloud CLIs does this org use — one, both, neither? | — *(ask)* | decides which rows of §4 you run |

There is no safe default for 4 and 5. A guessed tracker URL produces plausible, broken links in every PR body.

---

## §1. `env.sh` — the single switch

[`agent-knowledge/env.sh`](../agent-knowledge/env.sh) is the one file that knows where this machine's work lives. Everything else in the harness reads it instead of re-deriving paths, which is what makes an org change one edit rather than a grep.

**Read what is there before writing.** It still carries the previous org's values — expected, not a bug.

```sh
cat "${HARNESS_HOME:-$HOME/.agent-knowledge}/env.sh"
```

Set the values from §0's answers, preserving the `${VAR:-default}` form and the comments:

```sh
export WORK_ROOT="${WORK_ROOT:-$HOME/<new>/git-repos}"
export BEADS_DB="${BEADS_DB:-$WORK_ROOT/.beads}"
export HARNESS_DOCS="${HARNESS_DOCS:-$HOME/<new>/docs}"
export JIRA_BASE_URL="${JIRA_BASE_URL:-https://<neworg>.atlassian.net}"
export ACTIVE_ORG="${ACTIVE_ORG:-<neworg>}"
```

Keep the paths `$HOME`-relative. That is what lets the file survive a username change untouched.

**Two consequences you must not skip:**

- **If `WORK_ROOT` changes, the hive moves with it.** `bd` does not search for its database; `BEADS_DB` is the only thing that finds it. Move `.beads` to the new `WORK_ROOT`, then re-run §6 check 1.
- **A runtime whose config is JSON cannot source a shell file.** Where a runtime carries a literal copy of `BEADS_DB` (Claude Code's `settings.json` → `env.BEADS_DB` is the common case), update it in the same edit. `env.sh` documents this as the one unavoidable duplicate; if the two disagree, they disagree *silently*.

**Then, in a fresh login shell:**

```sh
exec $SHELL -l
echo "$WORK_ROOT $BEADS_DB $ACTIVE_ORG"
```

**Expected:** three non-empty values matching what you just wrote.
**If empty:** a shell profile is not sourcing `env.sh` — go to §6 check 3.

---

## §2. Seed the new org tier

`references/` is portable and comes with you. `orgs/<org>/` is instance knowledge and starts empty. The rule that decides which is which is [`core/protocols/knowledge-tiers.md`](../core/protocols/knowledge-tiers.md) — read it before moving any content.

```sh
mkdir -p "${HARNESS_HOME:-$HOME/.agent-knowledge}/orgs/$ACTIVE_ORG"
ls -d "${HARNESS_HOME:-$HOME/.agent-knowledge}/orgs"/*/
```

**Expected:** the new org directory, listed alongside the previous org's.

**Do not delete the previous org's directory.** `knowledge-search.sh` searches **every** org unconditionally, so that estate's knowledge stays findable as precedent. `ACTIVE_ORG` labels where new writes go; it must never narrow a read.

Then create the first file, `orgs/<org>/clusters.md`, and tell the user plainly that it is a **shape, not data** — you cannot invent a cluster registry, and an invented one is worse than an absent one. At minimum it answers, per cluster: **name · tier · cloud/provider · owning team · kube context · delivery mode** (tracks main vs pinned). Above the table, state explicitly which attributes the *name* does **not** encode — a suffix read as "test" that actually belongs to a customer's naming scheme has promoted production ahead of its staged ticket more than once.

**If the file stays empty:** that is acceptable on day one. Agents must degrade by saying "no cluster registry for this org" — never by inferring one from cluster names.

---

## §3. Carrying knowledge across the boundary

When you move an entry out of `references/` into the new org tier — or out of the previous org's tier into `references/` because it turned out to be method — two constraints apply. Both are load-bearing; both are in [`core/protocols/knowledge-tiers.md`](../core/protocols/knowledge-tiers.md).

**Basenames must not collide across tiers.** `orgs/acme/learnings-istio.md` beside `references/learnings-istio.md` makes every `learnings-istio.md#12` citation ambiguous, and the usage counter is keyed on basename, so the two files merge into one meaningless series. Drop the `learnings-` prefix in the org tier: `orgs/acme/istio.md`, cited as `orgs/acme/istio.md#4`.

**Tombstone; never renumber.** Leave a one-line stub at the old number:

```markdown
12. MOVED → `orgs/acme/istio.md#4` (instance knowledge: per-cluster revision inventory).
```

Renumbering to close the gap breaks every bare `#N` reference in bd memories, PR comments, and transcripts you cannot rewrite — and a corpus of any age has hundreds. The failure is not a dead link; it is a live link to the wrong entry.

**Verify a move actually landed:**

```sh
"${HARNESS_HOME:-$HOME/.agent-knowledge}/scripts/knowledge-search.sh" <a term from the moved content>
```

**Expected:** the content still appears — under the `### org:` section now instead of `### learnings`.
**If it appears nowhere:** the move deleted knowledge. Restore it before continuing.

---

## §4. Authentication

None of this can be automated. Print it as a numbered list for the user, then **verify each one** rather than assuming it happened.

| # | Ask the user to run | Verify with | Success looks like |
| --- | --- | --- | --- |
| 1 | `gh auth login` | `gh auth status` | `Logged in to github.com account <user>` |
| 2 | your own runtime's sign-in | you are running, so this is already true | — |
| 3 | the cross-model worker runtime's login | its `login status` equivalent | a logged-in account line, not an error |
| 4 | cloud CLI A login *(if §0.5 says so)* | its "who am I" command | one non-empty active account |
| 5 | cloud CLI B login *(if §0.5 says so)* | its "who am I" command | an identity document, not an error |

**If a verify command fails:** re-prompt once, then record it as UNVERIFIED in your final report. Never write "authenticated" for something you did not observe.

**MCP servers** re-authenticate on first use — nothing to do now, but the first call to each will interrupt whatever it is doing.

---

## §5. Clear the previous org's credentials — before any real work

Do this before the first task, not after. Anything that authenticated to the previous employer's systems is their property and is now sitting on hardware they do not control.

```sh
ls -d ~/.mcp-auth ~/.aws ~/.kube ~/.config/<cloud-sdk> 2>&1
```

**Expected after cleanup:** "No such file or directory" for each, then re-auth per §4.

**Why this outranks a rotation note:** an MCP auth store holds live OAuth tokens for the previous org's issue tracker, chat, dashboards, and incident tooling. That is working access, not a stale artifact. Confirm with the user that it is cleared; do not assume they read a warning.

**Do not blanket-delete a runtime's main config file** just because it contains an account identity. Those files typically carry both the old account *and* substantial project state the harness relies on. Have the user sign in again — that replaces the account without discarding the state. Delete the credential stores; edit the config.

Also rotate any token that was ever stored in plaintext in a config file, and treat every kubeconfig from the previous org as gone.

---

## §6. Sanity-check placement

Everything here checks that things are **where they belong**, not merely that they exist. Present is not correct: a hive in the wrong directory, or a second `BEADS_DB` winning over `env.sh`, looks completely healthy right up until it loses data.

### 1. `bd` resolves from a sibling directory

`bd` does not walk up the tree. `BEADS_DB` does all the work, so it must resolve from anywhere — not just from inside the hive's own directory.

```sh
mkdir -p "$WORK_ROOT/.placement-check" && (cd "$WORK_ROOT/.placement-check" && bd where)
```

**Expected:** a path ending in `/.beads`, equal to `$BEADS_DB`.
**If it prints a different path or fails:** `BEADS_DB` is not exported into this shell (§1), or the runtime's JSON config disagrees with `env.sh` (check 3). Clean up with `rmdir "$WORK_ROOT/.placement-check"`.

### 2. `.beads` is beside the repos, never inside one

```sh
ls -d "$WORK_ROOT/.beads" && find "$WORK_ROOT" -maxdepth 3 -name .beads -not -path "$WORK_ROOT/.beads"
```

**Expected:** the first path exists; the `find` prints **nothing**.
**If `find` prints a path inside a repo:** a nested hive gets committed by accident and dies with that repo at the next job change. Move it out. A `<repo>/.beads` **symlink** is the one allowed exception — a compatibility shim for shells still holding the old pin, safe to delete once every session has cycled.

### 3. Exactly one `BEADS_DB` definition wins

```sh
grep -n 'BEADS_DB\|agent-knowledge/env.sh' ~/.zshenv ~/.bashrc ~/.bash_profile 2>/dev/null
```

**Expected:** each profile that exists has **exactly one** line sourcing `env.sh`, and **no** raw `export BEADS_DB=` of its own. Any runtime JSON config that pins `BEADS_DB` has exactly one such key, equal to `$BEADS_DB`.

**If a profile carries a raw pin:** delete it. It is sourced *after* `env.sh` and silently overrides it — correct today, wrong the moment `env.sh` is edited, which defeats the entire point of a single switch.
**If a runtime config disagrees with `env.sh`:** fix the runtime config. Agents do not read your shell environment; that literal is load-bearing.

### 4. Both knowledge tiers are populated and searchable

```sh
ls "${HARNESS_HOME:-$HOME/.agent-knowledge}"/references/learnings-*.md | wc -l
ls -d "${HARNESS_HOME:-$HOME/.agent-knowledge}"/orgs/*/
"${HARNESS_HOME:-$HOME/.agent-knowledge}/scripts/knowledge-search.sh" <a term you know is in the corpus> | grep '^###'
```

**Expected** from the third command — all of these section headers:

```
### bd memories
### learnings (project)
### org: <neworg> (instance knowledge — ACTIVE)
### org: <previous-org> (instance knowledge)
### reading (external notes)
### domain docs
```

**If you get `### orgs (instance knowledge)` with "no org knowledge yet":** the tier exists but holds no `.md` file — go back to §2.
**If the new org is missing but the previous one is present:** `orgs/<neworg>/` is empty, or `ACTIVE_ORG` is unset so nothing is marked ACTIVE.
**If `### org:` sections are missing entirely** while `orgs/*/` clearly has content: the search is filtering by `ACTIVE_ORG`. That is the invariant violation — fix the script, not the data.
**If `### domain docs` is absent:** `HARNESS_DOCS` points at a directory that does not exist yet. Fine on day one; create it and say so.

### 5. The hive actually carries memories

```sh
bd memories --json | jq 'keys|length'
python3 -c "import json;print(sum(1 for l in open('$BEADS_DB/issues.jsonl') if l.strip() and json.loads(l).get('_type')!='issue'))"
```

**Expected:** both non-zero. The second is the important one — see §7.
**If the first is 0 but the second is not:** the database server is not running, or `BEADS_DB` is wrong.
**If the second is 0:** stop. Do not start `bd`. Go to §7.
**If the second raises instead of printing a number:** the file is malformed. That is *could not measure*, not zero — inspect it, and treat it as neither a pass nor a fail.

**Count by parsing, never with `awk` or `grep`.** A line filter counts **blank lines** as memories: one issue plus two stray newlines reports 2 when the true count is 0. The false answer is always the reassuring one, on exactly the file this check exists to reject.

### 6. No previous-machine paths left in live config

```sh
grep -rl "/Users/<old-username>" ~/.agent-knowledge ~/.<runtime-dirs> 2>/dev/null \
  | grep -vE '/(sessions|history|shell-snapshots|projects|statsig|logs?|cache|archived_sessions)/'
```

**Expected:** empty.
**If not empty:** rewrite those files and **report which ones** — whatever did the path rewrite missed a surface, and it needs that path next time.

The exclusion filter matters: session logs and history legitimately contain old paths as *records* of what happened. Rewriting those destroys an audit trail and fixes nothing. Only live config counts.

### 7. The hooks fire

Configured hooks that silently do not run are a harness's most expensive failure mode — everything looks normal and nothing is captured.

List every hook command your runtime has configured, then check each one resolves on disk and its interpreter is on `PATH`. At minimum the harness expects: the learning-capture gate (on sub-agent-stop **and** user-prompt-submit), the pre-compaction sync, and the rtk pre-tool-use wrapper. See [`hook-installation.md`](hook-installation.md).

**Expected:** no missing paths, and every interpreter resolves.
**If `rtk` is missing:** the pre-tool-use hook fails on **every** shell call. Install it first — this is the one that makes a session unusable rather than merely degraded.

Finally:

```sh
"${HARNESS_HOME:-$HOME/.agent-knowledge}/scripts/drift-check.sh"
```

**Expected:** either an all-clear line (exit 0), or a warnings header followed by that many bullet lines (exit 1). Warnings on day one are normal — a stale graph, an overdue consolidation. **A crash or empty output is not.**

---

## §7. Three things that fail silently

**An export that omits memories writes an empty corpus.** On a cold start `bd` rebuilds the database from `.beads/issues.jsonl`. If that file came from an issues-only export, the entire memory hive is **silently gone** — no error, no warning, just an empty corpus that looks like a fresh install.

```sh
python3 -c "import json;print(sum(1 for l in open('$BEADS_DB/issues.jsonl') if l.strip() and json.loads(l).get('_type')!='issue'))"    # MUST be non-zero
```

**Parse, do not grep.** An `awk`/`grep` line filter counts blank lines as memories and returns a reassuring non-zero for a file holding none — a false pass on the exact file this assertion exists to reject.

**If it is zero:** do not start `bd` — the cold start is what does the damage. Recover from the source machine with the only procedure that holds:

```sh
bd export --all -o /tmp/full.jsonl     # a SCRATCH path, never .beads/issues.jsonl
python3 -c "import json;print(sum(1 for l in open('/tmp/full.jsonl') if l.strip() and json.loads(l).get('_type')!='issue'))"
bd dolt stop                           # stop the server BEFORE touching .beads
cp /tmp/full.jsonl "$BEADS_DB/issues.jsonl"
python3 -c "import json;print(sum(1 for l in open('$BEADS_DB/issues.jsonl') if l.strip() and json.loads(l).get('_type')!='issue'))"
# then run NO further bd command
```

**The order is load-bearing.** Export while the database server is still up, verify, and only then stop it and copy. Stopping first would make the export itself run against a stopped server, and it would put a tool invocation *after* the file is in place — which is the thing that re-breaks it.

**Exporting straight at the canonical path does not stick.** `bd export --all -o .beads/issues.jsonl` writes the full file, and the tool's own default-path auto-export rewrites it issues-only within the same second. Intermittent — it will not reproduce on demand, and it has left the canonical file issues-only more than once, days apart. Exporting to a different path is stable and a plain `cp` does not race. Even a *read-only* `bd memories --json` afterwards has been enough to re-break it, so the final "run no further command" step is load-bearing rather than caution. Stop the database server before copying `.beads`.

**Editing a runtime's hooks config re-arms its trust prompt.** Headless execution then **skips untrusted hooks**, so a capture gate becomes a no-op and workers stop persisting learnings entirely. No error; the workers keep returning plausible output and the knowledge just never lands. After any hooks-config edit, have the user run one interactive session and accept the prompt, then dispatch one trivial worker and confirm the memory count went up. **A worker that returns text is not evidence the gate ran.** If you cannot confirm it, say so: *"capture gate: UNVERIFIED."*

**A health check that greps formatted output silently becomes a no-op.** Two checks here once counted memories by grepping human-readable CLI output; the tool changed its format and both returned 0 forever, cheerfully reporting "all clear" against a full hive. Count from a machine-readable surface, and make **"could not measure" distinguishable from "zero"**.

---

## §8. Cadence, learned the hard way

**Consolidate at ~120 memories, not 700.** A backlog that reached ~700 needed a sharded, multi-agent pass measured in hours, purely because it was several cycles overdue. At ~120 it is one agent and no sharding. Corpus growth is the system working — the fix is cadence, not less capture.

**Re-baseline the read heatmap.** Usage metrics from the previous org describe a corpus you have just re-tiered; check them again after a couple of weeks of real work. A file with heavy work and zero reads is a **discoverability gap**, not a low-value file. These numbers rank and detect gaps; they never justify pruning.

**Before the next move, promote anything path-keyed.** Runtime-native memories that are scoped to a working directory do not follow a repo move and will not load under a new path — knowledge stored there goes quietly missing and gets rebuilt from scratch. Anything durable belongs in `references/` (portable) or `orgs/<org>/` (instance).

---

## Final report

Close out with four lists, kept separate:

1. **Verified working** — with the check that proved it.
2. **UNVERIFIED** — done, but you could not observe success. Name the check you could not run.
3. **Still broken** — with the specific next action.
4. **Anything in this runbook that turned out to be wrong.** Fix it here, then say that you did.
