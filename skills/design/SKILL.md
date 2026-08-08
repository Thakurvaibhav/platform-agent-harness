---
name: design
description: >
  Design an infra system, subsystem, or API (CRD/XRD/chart contract), new or inside the
  existing estate. Locks requirements first, builds a constraint inventory, generates 2-3
  candidate shapes with diagrams, scores them with a multi-model judge panel (2 Anthropic +
  1 GPT-class) that removes complexity rather than scoring it, and emits a grounded
  technical design. Trigger phrases: "design a system",
  "design the API/CRD/XRD for", "how should we structure", "/design", "system design for",
  "architect this", "what shape should X take". Use for design; use adopt-eval for
  should-we-adopt-X selection decisions.
allowed-tools: [Read, Bash, Grep, Glob, Write, Agent, AskUserQuestion]
---

# design — grounded infra design with a multi-model panel

**Thin orchestrator. Holds no methodology.** The single source of truth is:

- `core/protocols/design-framework.md`

**Step 0: read it.** If it changes, this skill inherits the change — never copy its content here.

Also read `core/protocols/code-quality.md` (R1 offline proof, R2 read-the-source)
and your environment/topology reference before Phase 1.

## Flow

### 0. Requirements lock — 10 lines, then stop

Problem · success test · **non-goals** · consumers. Get an explicit nod before touching
Phase 1. Do not proceed on silence, and do not skip this because the ask "seems clear" —
a design torn down mid-session for unclear requirements costs far more than this gate.

### 1. Constraint inventory — derive, then ask

Run it **every time**. Product constraints may be thin; **platform constraints never are**
(clusters, CNI, DNS, GitOps, ingress/egress, policy engine). If the human ends up asking
"what are we already using for this?", Phase 1 was skipped or not surfaced.

Build it yourself first. **Never open with a questionnaire.**

```bash
agent-knowledge/scripts/knowledge-search.sh <domain keywords>
```

Then, per the framework's source list: sibling implementations, your environment/topology reference, domain
learnings, live cluster state, the CRD/API schema, CI gates.

Classify every item **Hard constraint / Convention / Preference** with the evidence each class
requires. Separately list immutable-after-create fields and anything nothing validates.

Present the table, then ask the human only to **correct and fill gaps** — via
`AskUserQuestion` where the answer changes the design. State your assumptions explicitly
rather than asking about them.

**Gate: the human challenges the table before any design exists.** This is the phase that
prevents the expensive rework.

### 2. Candidate shapes

2–3 shapes that differ in *approach*. Disqualify (don't score) any that violates a hard
constraint, and say why.

**Each candidate ships with a topology diagram.** Do not wait to be asked — if the human has
to request a diagram, the doc was already illegible.

### 3. Judge panel — blind round 1

Dispatch all three **in one message** so they run in parallel and cannot see each other.

- **J1 Anthropic — fit & correctness:** `Agent(subagent_type="general-engineer", model="opus")`
- **J2 Anthropic — operability:** `Agent(subagent_type="general-engineer", model="opus")`
- **J3 GPT — adversarial:**
  ```bash
  timeout 900 agent-knowledge/scripts/codex-dispatch.sh general-engineer \
    "<candidates + constraint table written to a FILE; pass the path>" <repo-dir> \
    > /tmp/design_j3.out 2>&1 < /dev/null
  ```

Write candidates and constraints to a file and pass the path — never inline them in a shell
argument; backticks in a config sketch are command substitution.

Each judge gets: the requirements lock, the constraint table, all candidates, the rubric.
**No judge gets another judge's output in round 1.** Tell each: *"Do not dispatch further
workers."*

Every judge must answer one question explicitly: **"name any component that can be removed
without losing a stated requirement."** A non-empty answer sends the candidate back to
Phase 2 — complexity is a defect to remove, not a score to lower.

### 4. One revision round, then stop

**Judges pick different winners** → round 2: each sees the others' picks and rationale, and
may revise on better evidence. Same winner with differing scores is not a split — do not
escalate on score arithmetic.

**Two rounds, then stop.** Still split → **surface it**: both positions, both rationales,
the evidence each rests on. Never average scores. Never fabricate consensus — a surviving
2-1 split is the signal you ran a mixed-model panel to get.

### 5. Synthesise and write

Winner + grafted ideas from runners-up. Emit the framework's deliverable sections.

**Output discipline — the reader implements from this:**
tables, mermaid, config sketches. No prose walls, no summary-of-the-summary. Every claim
grounded (`file:line` / live state / source at our version) or tagged `UNVERIFIED (assumption)`.

### 6. Route

Write to `docs/<topic>/design/<name>.md`. Never edit an existing design
doc in place — new file, and link the prior one if it supersedes.

## Boundaries

- **Not** for should-we-adopt-X selection → `adopt-eval`.
- **Not** for implementing the design → hand to the specialist agent.
- Do not skip Phase 1 because the design "seems obvious". Constraints discovered late are the
  entire cost this skill exists to avoid.
- Do not collapse to one candidate to save time. One candidate converges by review rounds.
