#!/usr/bin/env python3
"""discipline.py - the three mechanical gates, one tool.

    discipline.py comment  [--staged | --base REF | -]
    discipline.py test     [--staged | --base REF | -]
    discipline.py pr-body  [--pr N | --file PATH | -]

Exit: 0 clean, 1 findings, 2 usage error or unresolvable base.

This replaces three separate shell gates, which were three wrappers around three
python3 -c bodies with an identical argument front end. The wrappers were the
duplication; the three analyses were not, and they stay separate below. See
"Why there is no shared diff parser".


Why there is no shared diff parser
----------------------------------
The comment gate is a stateful parse: it tracks file AND hunk boundaries, keeps
a running +line number so it can report file:line, carries block-comment and
docstring state across lines, and inspects context and removed lines to know
when an added run ends. The test gate reads only "+++" headers and "+" lines and
counts; it never sees a hunk header, never computes a line number, and has no
cross-line state. Giving it the comment gate's parser would hand it hunk and
context handling it does not have today, which is a behaviour change in a live
gate for about four lines saved. The pr-body gate parses no diff at all; its
input is markdown.

So the shared code here is the part that genuinely was identical: the argument
front end, resolve_base() (byte-identical between the two diff gates), and the
pipeline exit convention. Each analysis is ported unchanged.


comment: code-comment discipline
--------------------------------
Rules that authors reliably self-exempt from, turned into counts:
  1. No ticket IDs, PR numbers, dates, or author names in code comments.
  2. No comment block longer than MAX_COMMENT_LINES (default 2).
  3. No high comment density per file. The default is NO comment, and a ceiling
     alone does not catch many small comments that should not exist.
  4. No Python function/body docstring longer than MAX_DOCSTRING_LINES
     (default 13). Module and class docstrings are exempt at any length.

These are counts because "terse" is a judgment, and every author of a 10-line
block believes theirs is the justified exception.

Env: MAX_COMMENT_LINES (2), MAX_DOCSTRING_LINES (13), BASE_REF


test: test VOLUME
-----------------
The comment gate bounds prose; this bounds the other thing a reviewer keeps
writing by hand: a diff whose test half is out of proportion to the code it
covers. core/protocols/code-quality.md ("Test volume") asks for the contract to
be tested rather than the implementation, and the reliable tell that it was
ignored is bulk.

The bound is AFFINE, not a plain ratio:

    added test LOC  <=  FIXED + RATIO x added prod LOC

A plain ratio is unusable on a small diff, because a single test carries a fixed
cost (imports, fixtures, parametrize tables) that does not shrink with the
change. FIXED absorbs that; RATIO is the repo baseline.

Env: MAX_TEST_RATIO (1.2), TEST_FIXED_LINES (220), BASE_REF


pr-body: PR DESCRIPTION length
------------------------------
The complaint that produced this: PR bodies grew long enough that reviewers
could not find the change inside them. "Be concise" had been in the protocol and
lost every time, same as the comment rule before it, so this is a count.

The bound is on what a reader SEES before expanding anything:

    visible non-blank lines  <=  MAX_BODY_LINES (default 40)

Not counted, because none of it costs the reader scroll: everything inside a
<details> block (the <summary> line counts as 1), the trailing Claude Code /
Co-Authored-By / session footer, HTML comments including bot-injected blocks
such as CURSOR_SUMMARY, and blank lines.

Over the bound, the fix is to CUT: a trailing PR comment is read once, by
nobody. If the overflow is a durable finding, capture it with learn.sh so it
reaches the corpus. See *PR Descriptions* in references/shared-protocols-core.md.

Env: MAX_BODY_LINES (40)


Base ref for the two diff gates, first that resolves: --base / $BASE_REF, the
PR's own baseRefName, origin/HEAD, then `main` with a warning; none resolving =
exit 2, gate did not run.


Known exit-code deviation, carried over deliberately
----------------------------------------------------
Our convention reserves exit 2 for "could not measure". The pr-body gate returns
1, not 2, when its input could not be produced at all: `--file` on a missing path
and the default branch mode when `gh pr view` fails both exit 1, because the old
shell pipeline reported `cat`/`gh` failure through pipefail and 1 is what those
commands return. Measured on the originals before this merge. Preserved rather
than fixed so the merge changes nothing; it is reported as a defect to fix
separately.
"""

import os
import re
import shutil
import subprocess
import sys

KINDS = ("comment", "test", "pr-body")


# ---------------------------------------------------------------- shared

def resolve_base(self_name, base):
    """Return (ref, source), or None when nothing resolves.

    The default branch is not always `main`, and a gate pointed at the wrong
    base measures an unrelated diff without ever erroring.
    """
    ref = base or os.environ.get("BASE_REF", "")
    src = "explicit"
    if not ref and _which("gh"):
        ref = _capture(["gh", "pr", "view", "--json", "baseRefName",
                        "-q", ".baseRefName"])
        src = "PR baseRefName"
    if not ref:
        ref = _capture(["git", "symbolic-ref", "--quiet",
                        "refs/remotes/origin/HEAD"])
        if ref.startswith("refs/remotes/origin/"):
            ref = ref[len("refs/remotes/origin/"):]
        src = "origin/HEAD"
    if not ref:
        ref = "main"
        src = "FALLBACK"
        err("%s: no --base, no PR context, origin/HEAD unset - falling back to main." % self_name)
        err("%s: if that is not this repo default branch, pass --base, or repair with: git remote set-head origin -a" % self_name)
    for cand in (ref, "origin/" + ref):
        if _run(["git", "rev-parse", "--verify", "--quiet",
                 cand + "^{commit}"])[0] == 0:
            return cand, src
    err("%s: CANNOT DETERMINE BASE - %s (%s) does not resolve to a commit." % (self_name, ref, src))
    err("%s: this gate did NOT run; nothing was measured. Pass --base <ref> or set BASE_REF." % self_name)
    return None


def err(msg):
    sys.stderr.write(msg + "\n")


def _which(prog):
    return shutil.which(prog) is not None


def _run(argv):
    try:
        p = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        return 127, ""
    return p.returncode, p.stdout.decode("utf-8", "replace")


def _capture(argv):
    return _run(argv)[1].strip()


def diff_input(kind, mode, base):
    """Return (text, producer_rc), or exit 2 when the base cannot be resolved."""
    if mode == "stdin":
        return sys.stdin.read(), 0
    if mode == "staged":
        rc, text = _run(["git", "diff", "--cached"])
        return text, rc
    info = resolve_base(kind + "-discipline", base)
    if info is None:
        sys.exit(2)
    ref, src = info
    rc, merge_base = _run(["git", "merge-base", ref, "HEAD"])
    merge_base = merge_base.strip()
    if rc != 0 or not merge_base:
        err("%s-discipline: no merge-base between %s and HEAD - cannot measure this diff." % (kind, ref))
        sys.exit(2)
    err("%s-discipline: base %s (%s), merge-base %s" % (kind, ref, src, merge_base[:8]))
    rc, text = _run(["git", "diff", merge_base + "...HEAD"])
    return text, rc


def finish(analysis_rc, producer_rc):
    """Reproduce `producer | python` under `set -o pipefail`.

    Pipefail returns the rightmost non-zero status, so a failing producer is
    only visible when the analysis itself exited 0.
    """
    sys.exit(analysis_rc if analysis_rc != 0 else producer_rc)


# ------------------------------------------------------------ kind: comment

SKIP_SUFFIX = (".md", ".markdown", ".rst", ".txt", ".mdx")
SKIP_PATH = ("CHANGELOG", "LICENSE", "NOTICE", "/vendor/", "/node_modules/")

LINE_COMMENT = {
    "#":  (".yaml", ".yml", ".sh", ".bash", ".tf", ".tfvars", ".py", ".toml",
           ".gotmpl", ".tpl", ".rb", ".conf", ".cfg", ".ini", ".gitignore",
           "Makefile", "Dockerfile", ".env"),
    "//": (".go", ".js", ".ts", ".tsx", ".jsx", ".java", ".rs", ".c", ".h",
           ".cpp", ".cs", ".kt", ".scala", ".proto", ".jsonnet", ".libsonnet"),
}

BANNED = [
    (re.compile(r"\b[A-Z][A-Z0-9]+-\d+\b"), "ticket ID"),
    (re.compile(r"(?<![\w#])#\d{3,}\b"), "PR/issue number"),
    (re.compile(r"\b\d{4}-\d{2}-\d{2}\b"), "date"),
    (re.compile(r"\b(?:added|changed|fixed|updated)\s+(?:on|by)\b", re.I),
     "changelog prose"),
]

BLOCK_OPEN = re.compile(r"^\s*(\{\{-?\s*)?/\*")
BLOCK_CLOSE = re.compile(r"\*/")

DOC_OPEN = re.compile(r"^(?:[rRbBuUfF]{0,2})(\"\"\"|''')")
PY_DEF = re.compile(r"^\s*(?:async\s+)?def\s")
PY_CLASS = re.compile(r"^\s*class\s")

DENSITY_MIN_LINES = 4
DENSITY_RATIO = 0.35

_QUOTE_CHARS = "\"'`"

in_block = False
path = None
findings = []
run = []
lineno = 0
density = {}
doc = {}
MAX = 2
MAX_DOC = 13


def openers(p):
    for tok, sfx in LINE_COMMENT.items():
        if p.endswith(sfx) or os.path.basename(p) in sfx:
            yield tok


def is_comment(text, p):
    global in_block
    s = text.strip()
    if in_block:
        if BLOCK_CLOSE.search(s):
            in_block = False
        return True
    if not s:
        return False
    if BLOCK_OPEN.match(s):
        if not BLOCK_CLOSE.search(s[s.index("/*") + 2:]):
            in_block = True
        return True
    for tok in openers(p):
        if s.startswith(tok):
            return True
    return False


def inline_comment(text, p):
    """The trailing comment on a line of code, or empty.

    is_comment() only matches a line that STARTS with a comment token, so a
    comment moved onto the end of a code line reached the gate as ordinary code
    and the BANNED scan never saw it; the ticket-ID rule was avoidable just by
    writing the comment inline. Quote state is tracked so a token inside a
    string literal (a URL, a fragment anchor) is not read as a comment opener: a
    false positive here is worse than the miss, because a gate that cries wolf
    is one somebody turns off.
    """
    toks = tuple(openers(p))
    if not toks:
        return ""
    quote, i, n = None, 0, len(text)
    while i < n:
        c = text[i]
        if quote:
            if c == "\\":
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in _QUOTE_CHARS:
            quote = c
            i += 1
            continue
        for t in toks:
            if text.startswith(t, i):
                return text[i:]
        i += 1
    return ""


def skip(p):
    return p.endswith(SKIP_SUFFIX) or any(x in p for x in SKIP_PATH)


def doc_flush():
    if doc["added"] and doc["kind"] in ("function", "body") and doc["n"] > MAX_DOC:
        findings.append((path, doc["line"], doc["n"],
                         "%s docstring is %d lines (max %d)" % (doc["kind"], doc["n"], MAX_DOC),
                         "narrative prose belongs in the PR body, not the source"))
    doc["open"] = False


def doc_reset():
    if doc.get("open"):
        doc_flush()
    doc.update(open=False, delim="", kind="", line=0, n=0, added=0,
               scope=None, wait=None)


def doc_scan(text, added, ln):
    if not path.endswith(".py"):
        return False
    s = text.strip()
    if doc["open"]:
        doc["n"] += 1
        if added:
            doc["added"] += 1
        if doc["delim"] in s:
            doc_flush()
        return True
    if not s or s.startswith("#"):
        return False
    m = DOC_OPEN.match(s)
    if m:
        d = m.group(1)
        indent = len(text) - len(text.lstrip())
        kind = doc["scope"] or ("module" if indent == 0 else "body")
        doc.update(kind=kind, line=ln, n=1, added=1 if added else 0,
                   delim=d, scope=None, wait=None)
        if d in s[m.end():]:
            doc_flush()
        else:
            doc["open"] = True
        return True
    # Scope of the NEXT statement: a def/class header, possibly spanning lines,
    # ends at the colon. Anything else clears it.
    if PY_DEF.match(text):
        doc["wait"] = "function"
    elif PY_CLASS.match(text):
        doc["wait"] = "class"
    if doc["wait"] and text.rstrip().endswith(":"):
        doc["scope"] = doc["wait"]
        doc["wait"] = None
    elif not doc["wait"]:
        doc["scope"] = None
    return False


def flush():
    global run
    if path and len(run) > MAX:
        findings.append((path, run[0][0], len(run),
                         "comment block is %d lines (max %d)" % (len(run), MAX),
                         run[0][1].strip()))
    run = []


def check_comment(text):
    global MAX, MAX_DOC, in_block, path, findings, run, lineno, density
    MAX = int(os.environ.get("MAX_COMMENT_LINES", "2"))
    MAX_DOC = int(os.environ.get("MAX_DOCSTRING_LINES", "13"))
    in_block = False
    path = None
    findings = []
    run = []
    lineno = 0
    density = {}
    doc_reset()

    for raw in text.splitlines(True):
        line = raw.rstrip("\n")

        # Reset in_block at every file AND hunk boundary: hunks are not
        # contiguous, so an unclosed block would stick the flag on forever.
        if line.startswith("+++ "):
            flush()
            doc_reset()
            in_block = False
            p = line[4:].strip()
            path = None if p == "/dev/null" else re.sub(r"^b/", "", p)
            continue
        if line.startswith("--- ") or line.startswith("diff --git"):
            flush()
            doc_reset()
            in_block = False
            continue
        if line.startswith("@@"):
            flush()
            doc_reset()
            in_block = False
            m = re.search(r"\+(\d+)", line)
            lineno = int(m.group(1)) - 1 if m else 0
            continue

        if not path or skip(path):
            continue

        if line.startswith("+"):
            lineno += 1
            body = line[1:]
            d = density.setdefault(path, [0, 0])
            if doc_scan(body, True, lineno):
                if body.strip():
                    d[1] += 1
                flush()
            elif is_comment(body, path):
                d[0] += 1
                run.append((lineno, body))
                for rx, label in BANNED:
                    if rx.search(body):
                        findings.append((path, lineno, 0,
                                         "%s in code comment" % label, body.strip()))
                        break
            else:
                if body.strip():
                    d[1] += 1
                # Density is deliberately NOT incremented: counting a code
                # line that carries a comment would change the reported ratio.
                frag = inline_comment(body, path)
                if frag:
                    for rx, label in BANNED:
                        if rx.search(frag):
                            findings.append((path, lineno, 0,
                                             "%s in code comment" % label, body.strip()))
                            break
                flush()
        elif line.startswith("-"):
            continue
        else:
            lineno += 1
            doc_scan(line[1:] if line[:1] == " " else line, False, lineno)
            flush()

    flush()
    doc_reset()

    for f, (c, code) in sorted(density.items()):
        total = c + code
        if c >= DENSITY_MIN_LINES and total and (float(c) / total) > DENSITY_RATIO:
            findings.append((f, 0, 0,
                             "comment density %d%% (%d comment / %d added lines) \u2014 default is none"
                             % (round(100.0 * c / total), c, total),
                             "a comment must earn its place; match the surrounding density"))

    if not findings:
        print("comment-discipline: clean")
        return 0

    print("comment-discipline: %d finding(s)\n" % len(findings))
    for p, ln, _n, why, snippet in findings:
        if len(snippet) > 96:
            snippet = snippet[:93] + "..."
        print("  %s:%d" % (p, ln))
        print("      %s" % why)
        print("      %s\n" % snippet)
    print("Rules: default is NO comment; ceiling %d lines when one is warranted;" % MAX)
    print("docstring ceiling %d lines on a function or a function body;" % MAX_DOC)
    print("never a ticket ID / PR number / date / author. Rationale goes in the PR body.")
    return 1


# --------------------------------------------------------------- kind: test

SRC = (".py", ".ts", ".tsx", ".js", ".jsx", ".go")
TEST_SKIP = ("/vendor/", "/node_modules/", "/migrations/", ".pb.go", "_pb2.py",
             ".generated.", "lock.json", "package-lock", "uv.lock")
TEST_DIR = ("/tests/", "/test/", "/__tests__/", "/e2e/")
TEST_SFX = ("_test.py", ".test.ts", ".test.tsx", ".test.js", ".test.jsx",
            ".spec.ts", ".spec.tsx", ".spec.js")
TEST_FN = re.compile(r"^\s*(?:async\s+)?def\s+test_|^\s*(?:it|test)(?:\.each\([^)]*\))?\s*\(")


def is_test(p):
    b = os.path.basename(p)
    return (any(d in p for d in TEST_DIR) or b.startswith("test_")
            or b.endswith(TEST_SFX))


def check_test(text):
    ratio = float(os.environ.get("MAX_TEST_RATIO", "1.2"))
    fixed = float(os.environ.get("TEST_FIXED_LINES", "220"))
    p = None
    test_loc = prod_loc = test_fns = 0

    for raw in text.splitlines(True):
        line = raw.rstrip("\n")
        if line.startswith("+++ "):
            q = line[4:].strip()
            p = None if q == "/dev/null" else re.sub(r"^b/", "", q)
            continue
        if not p or not line.startswith("+") or line.startswith("+++"):
            continue
        if not p.endswith(SRC) or any(s in p for s in TEST_SKIP):
            continue
        body = line[1:]
        if not body.strip():
            continue
        if is_test(p):
            test_loc += 1
            if TEST_FN.match(body):
                test_fns += 1
        else:
            prod_loc += 1

    allowed = fixed + ratio * prod_loc
    dens = (1000.0 * test_fns / prod_loc) if prod_loc else 0.0

    if test_loc <= allowed:
        print("test-discipline: clean (%d test / %d prod added LOC, allowance %d)"
              % (test_loc, prod_loc, round(allowed)))
        return 0

    print("test-discipline: 1 finding(s)\n")
    print("  %d added test LOC against %d added prod LOC" % (test_loc, prod_loc))
    print("      %d%% of the allowance (%d = %d + %.1f x prod); %d new test functions, %.1f per 1000 prod LOC"
          % (round(100.0 * test_loc / allowed), round(allowed), round(fixed), ratio, test_fns, dens))
    print("      test the contract, not the implementation \u2014 delete tests that pin module")
    print("      structure, exact internal call arguments, or library behaviour covered elsewhere\n")
    print("Allowance is affine, not a ratio: %d lines of fixed scaffolding plus %.1f" % (round(fixed), ratio))
    print("per added prod line. Over it, name the contract each extra test pins, or cut it.")
    return 1


# ------------------------------------------------------------ kind: pr-body

FOOTER = re.compile("|".join([
    "\U0001f916 Generated with", r"Generated with \[Claude Code\]",
    "Co-Authored-By:", "claude.ai/code/session_", "Claude-Session:"]))


def _collapse(m):
    inner = m.group(0)
    summary = re.search(r"<summary>(.*?)</summary>", inner, flags=re.S)
    return "<details> " + (summary.group(1).strip() if summary else "details")


def check_pr_body(body):
    max_lines = int(os.environ.get("MAX_BODY_LINES", "40"))

    if not body.strip():
        err("pr-body-discipline: empty body \u2014 nothing to check")
        return 0

    # Bot-injected HTML comment blocks were not written by the author, so they
    # must not consume the budget. A <details> costs the reader its <summary>.
    body = re.sub(r"<!--.*?-->", "", body, flags=re.S)
    body = re.sub(r"<details.*?</details>", _collapse, body, flags=re.S)

    lines = body.splitlines()
    end = len(lines)
    while end > 0 and (not lines[end - 1].strip() or FOOTER.search(lines[end - 1])
                       or lines[end - 1].strip() in ("---", "***", "\U0001f916")):
        end -= 1
    lines = lines[:end]

    visible = [l for l in lines if l.strip()]
    n = len(visible)

    if n <= max_lines:
        print("pr-body-discipline: clean ({}/{} visible lines)".format(n, max_lines))
        return 0

    heads = [l.strip() for l in visible if l.lstrip().startswith("#")]
    print("pr-body-discipline: {} visible lines, ceiling is {} (over by {})".format(
        n, max_lines, n - max_lines))
    if heads:
        print("  sections: " + " | ".join(h.lstrip("# ").strip() for h in heads))
    print("  Keep: ticket link, what changed, short validation, collapsed <details>.")
    print("  Cut the rest. If it is a durable finding, capture it with learn.sh instead.")
    print("  Rule: *PR Descriptions* in references/shared-protocols-core.md")
    return 1


# ------------------------------------------------------------------- main

HELP = {
    "comment": """discipline.py comment - mechanical gate for code-comment discipline.

  discipline.py comment                    # diff vs merge-base with the base branch
  discipline.py comment --staged           # staged changes (pre-commit)
  discipline.py comment --base origin/dev  # explicit base
  git diff ... | discipline.py comment -   # read a diff on stdin

Checks: banned ticket IDs / PR numbers / dates / attribution in comments; comment
blocks over MAX_COMMENT_LINES; per-file comment density; Python function and
in-body docstrings over MAX_DOCSTRING_LINES (module and class docstrings exempt).

Base ref, first that resolves: --base / $BASE_REF, the PR's own baseRefName,
origin/HEAD, then `main` with a warning; none resolving = exit 2, gate did not run.

Exit: 0 clean, 1 findings, 2 usage error or unresolvable base.
Env:  MAX_COMMENT_LINES (default 2), MAX_DOCSTRING_LINES (default 13), BASE_REF""",

    "test": """discipline.py test - mechanical gate for test VOLUME.

  discipline.py test                    # diff vs merge-base with the base branch
  discipline.py test --staged           # staged changes (pre-commit)
  discipline.py test --base origin/dev  # explicit base
  git diff ... | discipline.py test -   # read a diff on stdin

The bound is AFFINE, not a plain ratio:

    added test LOC  <=  FIXED + RATIO x added prod LOC

A plain ratio is unusable on a small diff, because a single test carries a fixed
cost (imports, fixtures, parametrize tables) that does not shrink with the
change. FIXED absorbs that; RATIO is the repo baseline.

Base ref, first that resolves: --base / $BASE_REF, the PR's own baseRefName,
origin/HEAD, then `main` with a warning; none resolving = exit 2, gate did not run.

Exit: 0 clean, 1 findings, 2 usage error or unresolvable base.
Env:  MAX_TEST_RATIO (default 1.2), TEST_FIXED_LINES (default 220), BASE_REF""",

    "pr-body": """discipline.py pr-body - mechanical gate for PR DESCRIPTION length.

  discipline.py pr-body                 # the PR for the current branch
  discipline.py pr-body --pr 1234       # a specific PR
  discipline.py pr-body --file body.md  # a body file, before `gh pr create`
  cat body.md | discipline.py pr-body - # read a body on stdin

The bound is on what a reader SEES before expanding anything:

    visible non-blank lines  <=  MAX_BODY_LINES (default 40)

Not counted: everything inside a <details> block (its <summary> counts as 1),
the trailing Claude Code / Co-Authored-By / session footer, HTML comments
including bot-injected blocks, and blank lines.

Over the bound, CUT. If the overflow is a durable finding, capture it with
learn.sh. See *PR Descriptions* in references/shared-protocols-core.md.

Exit: 0 clean, 1 findings, 2 usage error.
Env:  MAX_BODY_LINES (default 40)""",
}

USAGE = "usage: discipline.py {comment|test|pr-body} [options]  (-h for per-kind help)"


def main(argv):
    if not argv:
        err(USAGE)
        return 2
    if argv[0] in ("-h", "--help"):
        print(USAGE)
        print("\nKinds: " + ", ".join(KINDS))
        return 0
    kind = argv[0]
    if kind not in KINDS:
        err("unknown kind: %s" % kind)
        err(USAGE)
        return 2

    rest = argv[1:]
    mode = "branch"
    base = ""
    pr = ""
    path_arg = ""
    while rest:
        a = rest[0]
        if a == "-":
            mode = "stdin"
            rest = rest[1:]
        elif a in ("-h", "--help"):
            print(HELP[kind])
            return 0
        elif a == "--staged" and kind in ("comment", "test"):
            mode = "staged"
            rest = rest[1:]
        elif a == "--base" and kind in ("comment", "test"):
            if len(rest) < 2 or not rest[1]:
                err("--base needs a ref")
                return 2
            base = rest[1]
            rest = rest[2:]
        elif a == "--pr" and kind == "pr-body":
            if len(rest) < 2 or not rest[1]:
                err("--pr needs a number")
                return 2
            mode, pr = "pr", rest[1]
            rest = rest[2:]
        elif a == "--file" and kind == "pr-body":
            if len(rest) < 2 or not rest[1]:
                err("--file needs a path")
                return 2
            mode, path_arg = "file", rest[1]
            rest = rest[2:]
        else:
            err("unknown arg: %s" % a)
            return 2

    if kind == "pr-body":
        text, rc = _pr_body_input(mode, pr, path_arg)
        finish(check_pr_body(text), rc)
    text, rc = diff_input(kind, mode, base)
    finish(check_comment(text) if kind == "comment" else check_test(text), rc)


def _pr_body_input(mode, pr, path_arg):
    if mode == "stdin":
        return sys.stdin.read(), 0
    if mode == "file":
        try:
            with open(path_arg, "r") as fh:
                return fh.read(), 0
        except IOError as exc:
            # `cat` returns 1 on a missing or unreadable file, and the old shell
            # pipeline surfaced that through pipefail. Measured, not assumed.
            err("cat: %s: %s" % (path_arg, exc.strerror))
            return "", 1
    argv = ["gh", "pr", "view", "--json", "body", "--jq", ".body"]
    if mode == "pr":
        argv.insert(3, pr)
    rc, out = _run(argv)
    return out, rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
