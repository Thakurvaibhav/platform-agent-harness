#!/usr/bin/env bash
# pr-body-discipline.sh: mechanical gate for PR DESCRIPTION length.
#
# The complaint that produced this: PR bodies grew long enough that reviewers
# could not find the change inside them. "Be concise" sat in the protocol and lost
# every time, the same way the comment rule did before it, so this is a count.
#
# The bound is on what a reader SEES before expanding anything:
#
#     visible non-blank lines  <=  MAX_BODY_LINES (default 40)
#
# Not counted, because none of it costs the reader scroll:
#   - everything inside a <details> block (the <summary> line counts as 1)
#   - the trailing agent/session footer
#   - HTML comments, including bot-injected blocks such as <!-- CURSOR_SUMMARY -->
#   - blank lines
#
# Over the bound, the fix is to CUT. A trailing PR comment is read once, by
# nobody; if the overflow is a durable finding, capture it with learn.sh so it
# reaches the corpus instead. Body template: skills/create-pr/SKILL.md.
#
# Usage:
#   pr-body-discipline.sh                 # the PR for the current branch
#   pr-body-discipline.sh --pr 1234       # a specific PR
#   pr-body-discipline.sh --file body.md  # a body file, before `gh pr create`
#   cat body.md | pr-body-discipline.sh - # read a body on stdin
#
# Exit: 0 clean, 1 findings, 2 usage error.
# Env:  MAX_BODY_LINES (default 40)
set -uo pipefail

MODE="branch"
PR=""
FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)      MODE="pr"; PR="${2:?--pr needs a number}"; shift 2 ;;
    --file)    MODE="file"; FILE="${2:?--file needs a path}"; shift 2 ;;
    -)         MODE="stdin"; shift ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    *)         echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  stdin)  cat ;;
  file)   cat "$FILE" ;;
  pr)     gh pr view "$PR" --json body --jq .body ;;
  branch) gh pr view --json body --jq .body ;;
esac | MAX="${MAX_BODY_LINES:-40}" /usr/bin/python3 -c '
import os, re, sys

MAX = int(os.environ.get("MAX", "40"))
body = sys.stdin.read()

if not body.strip():
    print("pr-body-discipline: empty body, nothing to check", file=sys.stderr)
    sys.exit(0)

# Bot-injected HTML comment blocks (CURSOR_SUMMARY and friends) were not written
# by the author, so they must not consume the budget.
body = re.sub(r"<!--.*?-->", "", body, flags=re.S)

# A <details> block costs the reader one line: its <summary>. Collapse each to
# that single line so rendered output stays allowed without buying silence.
# `<details open>` renders EXPANDED on GitHub, so it costs full price and is skipped
# here: collapsing it too let any body pass by adding one attribute.
def collapse(m):
    inner = m.group(0)
    summary = re.search(r"<summary>(.*?)</summary>", inner, flags=re.S)
    return "<details> " + (summary.group(1).strip() if summary else "details")
body = re.sub(r"<details(?![^>]*\bopen\b).*?</details>", collapse, body, flags=re.S | re.I)

FOOTER = re.compile("|".join([
    "\U0001f916 Generated with", r"Generated with \[[^]]+\]",
    "Co-Authored-By:", r"/code/session_", r"^[A-Za-z-]+-Session:"]))

lines = body.splitlines()
# Trim the trailing footer block: walk up from the end past footer and blank
# lines, and stop at the first line that is real body content.
end = len(lines)
while end > 0 and (not lines[end-1].strip() or FOOTER.search(lines[end-1])
                   or lines[end-1].strip() in ("---", "***", "\U0001f916")):
    end -= 1
lines = lines[:end]

visible = [l for l in lines if l.strip()]
n = len(visible)

if n <= MAX:
    print("pr-body-discipline: clean ({}/{} visible lines)".format(n, MAX))
    sys.exit(0)

heads = [l.strip() for l in visible if l.lstrip().startswith("#")]
print("pr-body-discipline: {} visible lines, ceiling is {} (over by {})".format(
    n, MAX, n - MAX))
if heads:
    print("  sections: " + " | ".join(h.lstrip("# ").strip() for h in heads))
print("  Keep: ticket link, what changed, short validation, collapsed <details>.")
print("  Cut the rest. If it is a durable finding, capture it with learn.sh instead.")
print("  Body template: skills/create-pr/SKILL.md")
sys.exit(1)
'
