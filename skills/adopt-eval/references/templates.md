# Adoption Doc Templates

Two archetype skeletons (Assessment + Proposal) + shared stubs. Pick the archetype
via the handoff rule in the SKILL.md.

Every archetype starts with the same front-matter:

```yaml
---
title: <Proposal|Assessment>: <thing>
decision-status: locked | open-question | revisit-when | fallback | non-goal
verdict: Adopt | Adopt-with-caveats | Defer | Reject
archetype: assessment | proposal
ticket: <KEY>
---
```

---

## Archetype 1 -- Assessment / Decision-Note (`can-reject`)

> Verdict-first. Use when the answer might be NO.

```markdown
> **TL;DR / Recommendation** -- <the verdict in 2-3 sentences, decision FIRST>

## 1. What would <thing> solve?
## 2. Covered by the existing stack?
## 3. Coverage map
<Coverage-map stub>
## 4. The real gap
## 5. Alternatives
<Alternatives stub>
## 6. Maturity and exit-risk
## 7. Risks
<Risks stub>
## 8. Anticipated question
## 9. Verdict
## Non-Goals
## Open Questions
```

---

## Archetype 2 -- Proposal (WHAT / WHY / WHEN / HOW)

> One template serves both audiences: leadership reads TL;DR + WHAT/WHY;
> engineers read HOW. Keep main flow skimmable in ~2 min; push depth to Appendix.

```markdown
## Summary
| Author | @you |
| Status | DRAFT / IN REVIEW / APPROVED / REJECTED |
| Reviewers / Approvers | names |
| Last updated | date |
| Related | tickets, design docs, prior proposals, tool-landscape research doc |

**TL;DR** -- 2-3 sentences: what, why it matters, the ask.

# WHAT
## The proposal
## Problem / current state    <!-- Coverage-map stub -->
## Scope                      <!-- Goals / Non-Goals -->

# WHY
## Motivation and goals
## Cost of doing nothing
## Alternatives considered    <!-- Alternatives stub; headline the tool-landscape
                                  research; full comparison in linked research/ doc -->

# WHEN
## Timeline / phasing         <!-- Rollout-phases stub -->
## Dependencies and sequencing
## Guardrails                 <!-- Blocking Decisions + Reversibility stub -->

# HOW
## Approach                   <!-- how it FITS the existing stack; diagrams welcome -->
## Artifacts                  <!-- charts, CRs, manifests; or push to Appendix -->
## Rollout plan               <!-- pilot -> progressive -> GA -->
## Risks and mitigations      <!-- Risks stub: grounded, scoped to the decision -->
## Definition of done         <!-- concrete, cluster-testable -->
## Recommendation and ask
## Open questions
## Appendix                   <!-- tool-landscape link, benchmarks -->
```

---

## Shared Stubs

### Coverage-map stub
| Capability | How covered | Status |
|---|---|---|
| <capability> | <existing mechanism, or "--"> | Covered / Partial / Gap |

### Risks stub (default)
| Risk / seam | Scope | Status | Mitigation + evidence |
|---|---|---|---|
| <component x component> | `pilot` / `deferred` | `VERIFIED`/`PARTIAL`/`UNVERIFIED` | <mitigation + file:line / kubectl proof> |

### Incident-Ownership table (conditional -- only if ownership forks across teams)
| Failure seam | Symptom | Owner | Existing-tech interaction |
|---|---|---|---|
| <seam> | <observable failure> | existing/proposed/unknown | <which component owns what> |

### Alternatives stub
| Option | Why not | Revisit when |
|---|---|---|
| <alternative> | <reason rejected today> | <condition that would reopen it> |

### Rollout-phases stub
| Phase | Targets | Gate to advance | Rollback |
|---|---|---|---|
| 1 (monitor/audit) | <dev target> | <signal required> | <how to back out> |
| 2 (enforce, low-blast) | <test target> | ... | ... |
| 3 (prod) | <prod target set> | ... | ... |

### Reversibility stub
| Exit concern | Plan |
|---|---|
| Orphan inventory | <how we list what's left behind> |
| Cost / quota cleanup | <who reclaims> |
| Re-adoption path | <import/restore to prior tooling> |
| Uninstall / upgrade failure | <failure modes + recovery> |
