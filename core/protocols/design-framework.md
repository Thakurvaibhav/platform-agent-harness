# Design Framework

Canonical methodology for infra design. The `design` skill is a thin orchestrator over this file.

Covers a spectrum, not two modes. **Phase 1 always runs** — what varies is which half is thick:

| Constraint layer | Thin when | Never thin |
|---|---|---|
| **Product** — what this specific thing must do and integrate with | the capability is genuinely new | — |
| **Platform** — clusters, CNI, DNS, GitOps, ingress/egress, policy engine | — | **always.** It runs on your estate regardless. |

"Greenfield" almost always means *new product on an existing platform*. Treating it as
constraint-free is how a design reaches the point of the human asking "what are we already
using for this?" — a question Phase 1 exists to have answered before design starts.

---

## Output contract

The reader is a principal engineer who will implement this. Not a stakeholder deck.

- **Tables, diagrams, and config over prose.** A paragraph that could be a table row is a defect.
- **Every claim grounded.** A constraint cites `file:line`, an API schema, or live cluster
  state. A behavioral claim about a third-party tool cites its source at the version we run.
  Ungrounded assertions are marked `UNVERIFIED (assumption)` — never dropped, never asserted.
- **No summary of the summary.** One verdict line, then the substance.
- Mermaid for anything with more than three interacting components.

---

## Phase 0 — Requirements lock

**Before any constraint work.** Write, in **10 lines or fewer**:

| Field | Content |
|---|---|
| Problem | what breaks today, or what cannot be done |
| Success test | how you would know it works — observable, not aspirational |
| Non-goals | what this explicitly does not solve **(the load-bearing field)** |
| Consumers | who builds against it, and what they can be assumed to know |

**Get an explicit nod before Phase 1.** Do not proceed on silence.

This gate exists because the most expensive moment in a design session is the human saying
*"the doc has gone wild, let's take a step back and discuss requirements again"* — after the
design already exists. Ten lines up front is the cheapest possible guard against it. Re-lock
whenever requirements shift; say plainly that you are re-locking.

---

## Phase 1 — Constraint inventory

**Derive first, ask second.** Produce the inventory from the repo and live state, present it,
then ask the human only to correct and fill gaps. Never open with a questionnaire.

Sources, in order: sibling implementations of the same kind of thing · `clusters.md` ·
`learnings-*.md` for the domain · live cluster state · the CRD/API schema · CI gates.

Classify every item. **This taxonomy is the point of the phase:**

| Class | Evidence required | Effect on the design |
|---|---|---|
| **Hard constraint** | `file:line`, API schema, admission behavior, or live state | non-negotiable — design around it |
| **Convention** | count + examples ("11 of 13 charts do X") | follow it, or state why not |
| **Preference** | none — it is taste | **decide once, record, move on** |

Why it matters: an objection raised in review must name its class. *"I'd have done it
differently"* is a preference — it gets recorded, not litigated. Without this, every
objection arrives with equal weight and the design converges by attrition.

Also capture, as its own short list:

- **Immutable-after-create** fields — these are the expensive mistakes.
- **What nothing validates.** Where a wrong value renders, lints, and fails only at runtime.
  For each, say what the design does instead of relying on a check that does not exist.

**Output:** a constraints table the human can challenge *before any design exists*. Arguing
with the list is cheap; arguing with a finished design is not.

---

## Phase 2 — Candidate shapes

**Produce 2–3 genuinely different shapes. Never one.** Converging by picking is cheaper than
converging by review rounds.

They must differ in *approach*, not in detail — if two candidates differ only in naming, you
have one candidate. Force divergence: the simplest thing that could work · the one that
optimizes for the most likely change · the one that minimizes blast radius.

Per candidate: what it is (diagram or config sketch) · which constraints it satisfies and
which it strains · consumer ergonomics · failure modes · migration and rollback cost.

A candidate that violates a **hard constraint** is disqualified, not scored. Say so and drop it.

---

## Phase 3 — Multi-model judge panel

Three judges, **two Anthropic-class and one GPT-class**, so the panel is not one model
agreeing with itself. Divergence is signal.

| Judge | Model class | Lens |
|---|---|---|
| J1 | Anthropic | **Fit & correctness** — does it work, does it compose with the estate, does it honor the constraint table |
| J2 | Anthropic | **Operability** — what breaks at 3am, what the failure mode looks like, migration and rollback, what an on-call sees |
| J3 | GPT (Codex) | **Adversarial** — try to break each candidate; default to finding a required change |

Judges score **blind in round 1** — no judge sees another's output. A judge that has read
another's reasoning is no longer an independent sample.

Rubric, scored per candidate:

| Dimension | Scale |
|---|---|
| Hard-constraint violations | pass / fail (fail is disqualifying, not a low score) |
| Convention alignment | 1–5 |
| Operational blast radius | 1–5 (5 = smallest) |
| Migration + rollback cost | 1–5 (5 = cheapest) |
| Consumer ergonomics | 1–5 |
| Failure modes surfaced | count, not score — a judge finding more is doing better work |
| **Removable components** | **list, not score.** Each judge answers: *"name any component that can be removed without losing a stated requirement."* A non-empty list sends the candidate back to Phase 2 — it is not a lower score. |

### Disagreement is the output, not a problem to grind away

Averaging scores hides the disagreement that is the panel's whole value.

| Round | Trigger | What happens |
|---|---|---|
| 1 | always | blind independent scoring |
| 2 | **judges pick different winners** | each judge sees the others' picks and rationale, and may revise. Conceding to better evidence is expected; holding for consistency is not. |

**Two rounds, then stop.** Still split → **surface the split**: both positions, both
rationales, the evidence each rests on. Never fabricate consensus, never average to a fake
winner.

A persistent 2–1 split on operability is information you want. Two Anthropic models and a
GPT-class model disagreeing after seeing each other's reasoning is a genuine signal about the
design — more rounds would only convert it into false agreement, which is the thing this
framework exists to avoid.

**Different winners is a split. Differing scores with the same winner is not** — do not
escalate on score arithmetic; the scores are soft, the pick is observable.

---

## Phase 4 — Synthesis

Take the winner. **Graft the best ideas from the runners-up** — a losing candidate usually
solves one sub-problem better, and that part is free to take.

Deliverable:

| Section | Content |
|---|---|
| Verdict | one line: chosen shape + the single reason |
| Constraints | the Phase 1 table, with what changed after the panel |
| Candidates | table: shape × rubric, winner marked, disqualifications noted |
| Design | diagram + config sketch, grounded |
| Open splits | any unresolved panel disagreement, both positions |
| What nothing validates | the runtime-failure list from Phase 1, and how this design handles it |
| Implementation | ordered steps, each with its verification |

Record `UNVERIFIED (assumption)` items inline. They are the things to check first during
implementation.

---

## Anti-patterns

- **One candidate.** Guarantees convergence by review rounds.
- **Asking the human for constraints you could derive.** Derive, present, then ask.
- **Averaging judge scores.** Destroys the signal you paid three models for.
- **A judge that saw another judge's answer in round 1.** Not an independent sample.
- **Prose where a table would do.** The reader implements from this; make it scannable.
- **Designing before the constraint table is challengeable.** The expensive rework is always
  a constraint discovered late.
- **Designing before requirements are locked.** Phase 0 is ten lines. Skipping it is what
  produces a doc that has to be torn down mid-session.
- **Treating "greenfield" as constraint-free.** The platform layer is never thin.
- **Waiting to be asked for a diagram.** If the human asks for one, the doc was already
  illegible; ship it with the candidates.
- **Scoring complexity instead of removing it.** A removable component is a defect, not a
  lower score.
