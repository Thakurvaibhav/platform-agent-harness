# Skill: adopt-eval -- Interactive Adoption Evaluation

> Interactively evaluate whether to adopt a piece of infrastructure tech and produce
> a proposal or decision-note. Use when the user wants to assess a tool/pattern for
> the stack, weigh adoption, or turn a rough "we'd like to do Y" into a structured
> proposal.

Trigger phrases: "evaluate adopting", "should we adopt", "run an adoption eval",
"/adopt-eval", "do we need <tool>", "write a proposal for <tool>", "assess <tool>
for our stack".

---

## Operating principle: interactive, one gate at a time

Do NOT run the whole evaluation silently and dump a doc. Drive it as a conversation:
present each gate's question, gather evidence, show the gate result, and get a nod
before advancing. The human is in the loop at every gate. Surface assumptions; never
invent evidence you don't have.

---

## The flow

### 1. Intake

Ask the user for the stance block (or accept it if they pasted one):
```
thing:            <what tech / pattern>
decision-status:  open-question | locked | revisit-when | fallback | non-goal
scope-in:         <what's in>
scope-out:        <what's explicitly out>
trigger:          <the pain / aspiration that started this>
```
If `decision-status` is `open-question`, the gates may STOP and you write an
Assessment. Do not let the user pre-pick a Proposal archetype -- the verdict earns it.

### 2. Run the gates (one at a time)

```
Gate 1  Pain / Coverage   Is there real, QUANTIFIED pain? Does the existing stack cover ~80%?
                          [STOP if no pain / already covered / pain unquantified]
Gate 2  Fit & Interplay   Does it fit the platform (providers, GitOps, existing tools)?
                          How does it play with what's already running?
                          [STOP if conflicts unresolved]
Gate 3  Rollout / Risk    Can we stage it (dev->test->prod, monitor/audit-first, kill-switch)?
                          Blast radius? Ops cost? Pilot-selection test?
                          [STOP if not worth the squeeze]
Verdict  Adopt | Adopt-with-caveats | Defer | Reject
```

For EACH gate:
1. State the gate's question for THIS specific thing.
2. Name the one scoped evidence query the gate needs.
3. Gather what you can yourself (read-only only: kubectl get/describe, git grep,
   helm template, cloud CLI list/describe). NEVER mutate.
4. PAUSE and ask the human for any org-knowledge evidence not in a system.
5. Show the gate result (pass / stop + why) and the evidence behind it.

### 3. Tool-landscape (delegated)

Dispatch the tool-researcher sub-agent for the tool landscape only (versions,
alternatives, maturity, blast radius, integration). Everything else stays with you.

Require the appendix to state its premises explicitly. Two mechanics:
- PAUSE and confirm premises with the human before it touches the verdict.
- Ground every environment-dependent claim against LIVE config (kubectl the cluster,
  not just git grep). Tag anything unverified `UNVERIFIED (assumption)`.
- Persist the research as its own doc (standalone appendix, linked from the proposal).

### 4. Verdict -> archetype (handoff rule)

| Verdict | Allowed archetype |
|---|---|
| Reject / Defer | Assessment / Decision-Note only |
| Adopt-with-caveats | Proposal, but caveats MUST carry forward (Guardrails / Blocking Decisions) |
| Adopt | Proposal |

### 5. Fill the skeleton

Fill the selected archetype skeleton. Key output rules:
- Risk list with verification status (VERIFIED / UNVERIFIED); upgrade to
  Incident-Ownership table only if ownership forks across teams.
- Scope risks to the decision (pilot), not the end-state.
- Scale guardrail depth to blast radius.
- Non-Goals and Open Questions are required sections.
- Every risk and every Blocking Decision carries a live citation or is tagged UNVERIFIED.

### 5b. Cross-model peer review (REQUIRED before human sees it)

Dispatch an adversarial review via a different model/runtime:
```
codex-dispatch.sh general-engineer "<review prompt>" <dir>
```
The review critiques technical soundness, over-claims, completeness, and the
locked-vs-open split. Fold findings into the doc, then proceed.

### 6. Route the output

| Verdict / archetype | Lands in |
|---|---|
| Assessment (Reject/Defer/open-question) | `docs/<topic>/summaries/<date>-<thing>-decision-note.md` |
| Proposal | `docs/<topic>/design/<date>-<thing>-proposal.md` |
| Tool-landscape research | `docs/<topic>/research/<date>-<tool>.md` |

---

## Key rules (anti-patterns the framework prevents)

- **Anti-laundering**: Generic upstream "production-ready" is NOT "fits our stack."
  Re-test maturity claims against your constraints (Gate 2).
- **Premise-check**: Tool-research recommendations rest on premises. A wrong premise
  flips the answer. Surface and validate before the verdict.
- **Ground-every-claim**: Every env-dependent claim must be verified against LIVE config.
  `git grep` is the first check, not the last (settings may be chart defaults or live
  overrides absent from the repo).
- **Quantified pain**: Qualitative "it's a bottleneck" does not pass Gate 1. Require
  numbers or named instances.
- **Reversibility beyond rollback**: Require orphan inventory, cost/quota cleanup, the
  re-adoption path, and uninstall/upgrade failure modes.

---

## Boundaries

- Read-only evidence only. No mutating kubectl/helm/cloud CLI.
- The skill structures the thinking; it does NOT make the call. The verdict and final
  sign-off are the human's.
- Hold no methodology here -- if explaining a gate from memory, stop and read the
  framework docs instead.
