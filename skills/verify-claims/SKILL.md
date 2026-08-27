---
name: verify-claims
description: >
  Verify claims about third-party behaviour against upstream source at the version you run,
  one parallel worker per claim. Use when a design doc, research report, PR description, or
  learnings entry asserts how a tool/controller/library behaves and those assertions decide
  something. Trigger phrases: "verify these claims", "check this against the source",
  "is this actually true", "/verify-claims", "ground this doc", "R2 pass". Implements
  reflex R2 at fan-out width.
allowed-tools: [Read, Bash, Grep, Glob, Write, Agent, WebFetch]
---

# verify-claims — R2 at fan-out width

Reflex **R2** ([`core/protocols/code-quality.md`](../../core/protocols/code-quality.md)) says any
claim about third-party runtime behaviour must be backed by its source *at the version you run*,
cited `file:line`. Checking claims one at a time is why it gets skipped. This fans them out.

## When it pays

A document makes several load-bearing assertions about a tool you did not write — a
controller's reconcile behaviour, an admission check, a default, a flag's effect. Each is
independently checkable, so they parallelise perfectly.

**Not** for claims about your own code (read it), your cluster state (query it), or anything
where one grep settles it. Two claims is a grep; six is a fan-out.

## Flow

### 1. Extract claims to a file

Pull out the **falsifiable** assertions — ones a source read can settle. Skip opinions,
recommendations, and anything about your own repo.

```bash
cat > /tmp/claims.md <<'EOF'
1. <claim> | tool: <name> | version: <pinned version you run>
2. <claim> | tool: <name> | version: <pinned version you run>
EOF
```

**Write claims to a file and pass the path.** Never inline them in a shell argument —
backticks in a claim are command substitution, which both corrupts the prompt and executes
whatever is inside them.

**Every claim carries its version pin.** "Does the controller do X" is unanswerable; "does
controller 1.29.6 do X" is a source read. A claim without a version is not yet a claim — fix it
before dispatch.

### 2. Fan out, one worker per claim

Cap at **8 concurrent**. Beyond that you hit rate limiting and gain nothing.

Dispatch all in a single message so they run in parallel. Each worker gets **one claim only**
and no other worker's output.

Worker brief:

> Verify exactly this claim against the tool's SOURCE at the stated version. Find the
> repository, check out or fetch that version, read the relevant code, and cite `file:line`.
> Documentation, release notes, blog posts and issue threads are NOT evidence — they are
> frequently stale or aspirational. Return one of:
> **CONFIRMED** (+ `file:line` and the code that shows it) ·
> **REFUTED** (+ `file:line` and what the code actually does) ·
> **UNVERIFIABLE** (+ what you looked at and why it did not settle it).
> Do not soften a REFUTED into "partially correct". Do not dispatch further workers.

Mixed-runtime is better than uniform: send some claims through
[`agent-knowledge/scripts/codex-dispatch.sh`](../../agent-knowledge/scripts/codex-dispatch.sh)
(or your runtime's cross-model equivalent) so a second model class reads the same kind of
source. A model that wrote a claim is a poor choice to check it.

### 3. Report — never silently drop

| Verdict | What happens |
| --- | --- |
| CONFIRMED | annotate the claim with its `file:line` so the next reader need not re-verify |
| REFUTED | **correct the source document**, and say what it used to say |
| UNVERIFIABLE | tag `UNVERIFIED (assumption)` in place — never delete it |

Deleting an unverifiable claim destroys exactly the signal the reader needs. A claim you could
not check is information; silence is not.

Output:

```
claim                                  verdict        evidence
-------------------------------------  -------------  -----------------------------------
<short form>                           CONFIRMED      pkg/foo/bar.go:412
<short form>                           REFUTED        actually returns nil — bar.go:88
<short form>                           UNVERIFIABLE   source is generated; no upstream file
```

Lead with REFUTED and UNVERIFIABLE. A confirmed claim needs no attention.

## Why this exists

A learnings entry asserted that isolation between two environments came from a **cloud account
boundary**. The two environments actually **shared one account** — the isolation came from a
name-prefix glob, which is a far weaker guarantee. The claim sat in the knowledge base for weeks
and surfaced only during a consolidation sweep. One worker and one source read would have caught
it the day it was written.

That is the shape to watch for: a claim that names the *strongest plausible* mechanism for a
property you have observed, without anyone having checked which mechanism is actually
load-bearing.

Correcting a wrong claim in a knowledge base is cheap. Acting on one is not.
