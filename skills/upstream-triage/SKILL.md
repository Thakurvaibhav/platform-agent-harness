---
name: upstream-triage
description: |
  Decide what to do about a confirmed limitation or bug in a third-party dependency —
  plugin, controller, operator, library — and draft a clean upstream issue when filing
  is the answer. Use when you have verified a third-party tool does not do what we need:
  "is this a known issue", "should we file upstream", "file a bug against X", or after
  reflex R2 confirms the behavior in the source at your pinned version. Triages wait vs
  work-around vs file by checking whether the project is maintained and a fix is likely.
  Drafts and confirms before filing, never files automatically, and never leaks internal
  names or infrastructure detail into the issue body. Do NOT use for bugs in your own
  repositories.
---
# Skill: Upstream Triage

> When you confirm a limitation or bug in a third-party dependency (plugin, controller, operator, library), decide whether to wait, work around, or file upstream, and draft a clean, internal-info-free issue. Draft-and-confirm before filing; never auto-file.

---

## When to use

- You've confirmed (ideally by reading the source, Standing Reflex R2) that a third-party tool has a real limitation, bug, or missing feature that costs you work or blocks a goal.
- Before committing to a heavy workaround, knowing whether a fix is imminent changes the calculus.

## When NOT to use

- The problem is your own config/bug, not the dependency's.
- Trivial/cosmetic, or the workaround is cheap and the tool is clearly unmaintained.

## Procedure

1. **Confirm it's upstream, not you.** Reproduce or read the source at the version you run. Rule out misconfiguration.
2. **Search the project** -- issues, PRs, and discussions -- for the exact behavior. Capture: is it reported? open/closed? who closed it (maintainer vs. reporter)? any in-flight PR? maintainer intent/roadmap comments. Record issue/PR numbers + URLs + dates.
3. **Assess maintenance health** -- latest release + date, release cadence, open vs. closed issue counts, maintainer responsiveness, whether it's the officially-recommended option. Conclude: is a fix likely soon?
4. **Decide:**
   - Tracked + fix imminent: link/subscribe, don't file; note the workaround is interim.
   - Untracked (or self-closed/stale) + it costs you: draft an issue.
5. **Draft (generic, redacted).** Title + body with: a short summary, a MINIMAL repro using placeholder names (`svc-stable`/`svc-canary`, `/a`, `/b` -- NO internal service/cluster/org/host names), a link to any prior/related/closed issue, the proposed enhancement, the current workaround, and an offer to send a PR. Strip every internal identifier.
6. **Draft and confirm -- then file.** Present the draft + target repo to the user; file only on explicit go: `gh issue create --repo <owner/repo> --title "<t>" --body-file <f>`. Default is draft-and-confirm; never silently auto-file under the user's identity. Confirm the `gh` account first. **End the body with 🤖 on its own last line** — this lands in a stranger's repo under the user's name, so maintainers deserve to know an agent drafted it, and it sets expectations for the follow-up thread. See *Agent attribution: 🤖 sign-off* in [`core/protocols/safety-and-handoff.md`](../../core/protocols/safety-and-handoff.md).
7. **Close the loop.** Link the filed issue wherever the limitation is recorded (decision memory, Slack message, PR), and `bd remember` it.

## Output

- Triage verdict: is it tracked? is a fix likely? recommendation (wait / workaround / file).
- The strongest issue/PR references (numbers, URLs, dates).
- If filing: the draft, and after confirmation, the filed URL.
