---
name: stakeholder-comms
description: |
  Draft a team-facing message about a decision, tradeoff, or change — Slack, PR or RFC
  comment, email — so it is diplomatic, specific, and drives a decision rather than
  narrating. Use when writing a blurb for the team, announcing a change that affects
  others, explaining a tradeoff to stakeholders, or pushing back on a proposal without
  relitigating sign-offs already given. Produces a draft the user sends under their own
  name; Slack messages are drafted, never sent. Do NOT use for PR descriptions (see
  create-pr) or routine status replies.
---
# Skill: Stakeholder Comms

> Draft team-facing messages (Slack, PR/RFC, email) about a decision, tradeoff, or change so they're diplomatic, clear, and decision-driving -- without relitigating prior sign-offs or making anyone defensive.

---

## When to use

- Drafting a message to a team or another team about a decision, tradeoff, surfaced complexity, or asking them to choose or do cross-team work.
- Especially when the message touches someone else's prior decision, or asks another team for effort.

## When NOT to use

- Notes to self, status one-liners, commit messages, internal bd comments.

## Principles

- **Honor prior decisions.** Acknowledge any sign-off explicitly; don't relitigate. Frame newly-surfaced complexity as discovered during implementation -- blameless, not "the design was wrong."
- **Enable, don't block.** Lead with "ready to run either way"; you're confirming alignment, not resisting.
- **Neutral, symmetric options.** Present each path's value first, then cost. Don't stack the deck; make the lighter path visible without disparaging the chosen one.
- **Concrete, not alarmist.** Quantify complexity (real numbers, named artifacts) but keep the tone even.
- **Ask for a clear decision** and state what you need from them.
- **Redact + link out.** Strip internal-only details from anything external; link external/public docs over internal ones.
- **Format for the medium.** Short, bulleted, scannable. In Slack avoid markdown tables (won't render) and code-block tables (hard to copy) -- prefer bullets. Keep clickable links outside code blocks.
- **Offer to dial the tone** (softer/firmer) rather than guessing.

## Output

- The copy-paste-ready message.
- A one-line note on the tone/framing choices made, and an offer to adjust the lean.
