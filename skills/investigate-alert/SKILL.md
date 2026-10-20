---
name: investigate-alert
description: >-
  Investigate a firing alert from a Slack link/message or alert title to determine
  cause, scope, and impact. Read-only SRE triage. Use when the user asks to
  investigate, triage, or look into an alert, points at an alert in Slack, gives
  an alert name, or asks why an alert is firing.
---

# Investigate Alert

Read-only SRE triage using the
[`alert-investigator`](../../core/agents/alert-investigator.md) agent and
[`agent-knowledge/references/playbook-alert-investigation.md`](../../agent-knowledge/references/playbook-alert-investigation.md).

## What to do

1. Capture a **Slack link/message** or **alert title/name**, plus the user's context.
   If neither was supplied, ask for one. If Slack access is unavailable, use pasted
   text or the title and report missing thread context.
2. Dispatch `alert-investigator` through the runtime's supported delegation mechanism.
   Pass the alert input, constraints, and instruction: "Follow
   `agent-knowledge/references/playbook-alert-investigation.md`. Stay read-only.
   Return the triage card, separating evidence from assumptions."
   If delegation is unavailable or forbidden, follow the same agent and playbook directly.
3. Relay the triage card. Surface proposed learnings for approval. Show any Slack reply
   as a draft; never send it.

## Notes

- Never mutate resources, acknowledge/resolve/silence alerts, or implement remediation.
  Recommendations belong in `NEXT STEP` for a human.
- Use available Grafana, Prometheus, Loki, Sift, gcx, kubectl, gcloud, and aws read-only
  capabilities. Your incident-management tool, if you have one, is optional.
- For gcx query examples, consult
  [`references/alert-investigation-patterns.md`](references/alert-investigation-patterns.md).
