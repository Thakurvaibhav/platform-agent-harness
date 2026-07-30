#!/usr/bin/env bash
# comment-discipline.sh — mechanical gate for code-comment discipline.
#
# Enforces the two rules in shared-protocols-core.md that authors reliably
# self-exempt from, by turning them into counts instead of judgment calls:
#   1. No ticket IDs, PR numbers, dates, or author names in code comments.
#   2. No comment block longer than MAX_LINES (default 2). Need a third line?
#      It is PR-description material, not source.
#
# Rule 2 exists because "terse" and "one line where one line works" are
# judgments, and every author of a 10-line block believes theirs is the
# justified exception. A line count cannot be argued with.
#
# Usage:
#   comment-discipline.sh                    # diff vs merge-base with origin/main
#   comment-discipline.sh --staged           # staged changes (pre-commit)
#   comment-discipline.sh --base origin/dev  # explicit base
#   git diff ... | comment-discipline.sh -   # read a diff on stdin
#
# Exit: 0 clean, 1 findings, 2 usage error.
# Env:  MAX_COMMENT_LINES (default 2)
set -uo pipefail

MAX_LINES="${MAX_COMMENT_LINES:-2}"
BASE="origin/main"
MODE="branch"

while [ $# -gt 0 ]; do
  case "$1" in
    --staged)  MODE="staged"; shift ;;
    --base)    BASE="${2:?--base needs a ref}"; shift 2 ;;
    -)         MODE="stdin"; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *)         echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  stdin)  cat ;;
  staged) git diff --cached ;;
  branch) git diff "$(git merge-base "$BASE" HEAD 2>/dev/null || echo "$BASE")"...HEAD ;;
esac | MAX_LINES="$MAX_LINES" /usr/bin/python3 -c '
import os, re, sys

MAX = int(os.environ.get("MAX_LINES", "2"))

# Prose files are excluded outright. A markdown "## Heading" is not a code
# comment, and flagging them buries the real findings in noise — that false
# positive is exactly what makes a gate get ignored.
SKIP_SUFFIX = (".md", ".markdown", ".rst", ".txt", ".mdx")
SKIP_PATH   = ("CHANGELOG", "LICENSE", "NOTICE", "/vendor/", "/node_modules/")

# Comment openers by file type. Only what we actually author.
LINE_COMMENT = {
    "#":  (".yaml", ".yml", ".sh", ".bash", ".tf", ".tfvars", ".py", ".toml",
           ".gotmpl", ".tpl", ".rb", ".conf", ".cfg", ".ini", ".gitignore",
           "Makefile", "Dockerfile", ".env"),
    "//": (".go", ".js", ".ts", ".tsx", ".jsx", ".java", ".rs", ".c", ".h",
           ".cpp", ".cs", ".kt", ".scala", ".proto", ".jsonnet", ".libsonnet"),
}

# Ticket keys, PR/issue numbers, dates, and attribution. All banned in source.
BANNED = [
    (re.compile(r"\b[A-Z][A-Z0-9]+-\d+\b"),                      "ticket ID"),
    (re.compile(r"(?<![\w#])#\d{3,}\b"),                          "PR/issue number"),
    (re.compile(r"\b\d{4}-\d{2}-\d{2}\b"),                        "date"),
    (re.compile(r"\b(?:added|changed|fixed|updated)\s+(?:on|by)\b", re.I), "changelog prose"),
]

def openers(path):
    for tok, sfx in LINE_COMMENT.items():
        if path.endswith(sfx) or os.path.basename(path) in sfx:
            yield tok

# Block-comment openers/closers. Tracked with state, otherwise only the opening
# line counts and a 20-line /* ... */ essay slips through a line-comment-only
# gate untouched — which would make the whole check trivially avoidable.
BLOCK_OPEN  = re.compile(r"^\s*(\{\{-?\s*)?/\*")
BLOCK_CLOSE = re.compile(r"\*/")

in_block = False

def is_comment(text, path):
    global in_block
    s = text.strip()
    if in_block:
        if BLOCK_CLOSE.search(s):
            in_block = False
        return True
    if not s:
        return False
    if BLOCK_OPEN.match(s):
        # Single-line /* ... */ opens and closes on the same line.
        if not BLOCK_CLOSE.search(s[s.index("/*") + 2:]):
            in_block = True
        return True
    for tok in openers(path):
        if s.startswith(tok):
            return True
    return False

def skip(path):
    return path.endswith(SKIP_SUFFIX) or any(p in path for p in SKIP_PATH)

path = None
findings = []
run = []          # consecutive added comment lines: (lineno, text)
lineno = 0

def flush():
    global run
    if path and len(run) > MAX:
        findings.append((path, run[0][0], len(run),
                         "comment block is %d lines (max %d)" % (len(run), MAX),
                         run[0][1].strip()))
    run = []

for raw in sys.stdin:
    line = raw.rstrip("\n")

    # in_block is reset at every file AND hunk boundary: hunks are not
    # contiguous, so a block comment that opens in one hunk and closes in
    # unshown context would otherwise leave the flag stuck on forever.
    if line.startswith("+++ "):
        flush()
        in_block = False
        p = line[4:].strip()
        path = None if p == "/dev/null" else re.sub(r"^b/", "", p)
        continue
    if line.startswith("--- ") or line.startswith("diff --git"):
        flush()
        in_block = False
        continue
    if line.startswith("@@"):
        flush()
        in_block = False
        m = re.search(r"\+(\d+)", line)
        lineno = int(m.group(1)) - 1 if m else 0
        continue

    if not path or skip(path):
        continue

    if line.startswith("+"):
        lineno += 1
        text = line[1:]
        if is_comment(text, path):
            run.append((lineno, text))
            for rx, label in BANNED:
                if rx.search(text):
                    findings.append((path, lineno, 0, "%s in code comment" % label,
                                     text.strip()))
                    break
        else:
            flush()
    elif line.startswith("-"):
        continue          # removed line: no effect on the added-run
    else:
        lineno += 1
        flush()

flush()

if not findings:
    print("comment-discipline: clean")
    sys.exit(0)

print("comment-discipline: %d finding(s)\n" % len(findings))
for p, ln, _n, why, snippet in findings:
    if len(snippet) > 96:
        snippet = snippet[:93] + "..."
    print("  %s:%d" % (p, ln))
    print("      %s" % why)
    print("      %s\n" % snippet)
print("Rules: no ticket IDs / PR numbers / dates / authors in code comments;")
print("max %d lines per comment block. Longer rationale belongs in the PR body." % MAX)
sys.exit(1)
'
