#!/usr/bin/env bash
# test-discipline.sh — mechanical gate for test VOLUME.
#
# comment-discipline.sh bounds prose; this bounds the other thing a reviewer
# keeps writing by hand: a diff whose test half is out of proportion to the code
# it covers. The standard is "test the contract, not the implementation" (see
# core/protocols/code-quality.md), and the reliable tell that it was ignored is
# bulk — tests pinning module structure, exact internal call arguments, or
# library behaviour already covered elsewhere.
#
# The bound is AFFINE, not a plain ratio:
#
#     added test LOC  <=  FIXED + RATIO x added prod LOC
#
# A plain ratio is unusable on a small diff, because a single test carries a
# fixed cost (imports, fixtures, parametrize tables) that does not shrink with
# the change. FIXED absorbs that; RATIO is the repo baseline.
#
# Usage / exit / input forms are identical to comment-discipline.sh:
#   test-discipline.sh                    # diff vs merge-base with origin/main
#   test-discipline.sh --staged           # staged changes (pre-commit)
#   test-discipline.sh --base origin/dev  # explicit base
#   git diff ... | test-discipline.sh -   # read a diff on stdin
#
# Exit: 0 clean, 1 findings, 2 usage error.
# Env:  MAX_TEST_RATIO (default 1.2), TEST_FIXED_LINES (default 220)
set -uo pipefail

RATIO="${MAX_TEST_RATIO:-1.2}"
FIXED="${TEST_FIXED_LINES:-220}"
BASE="origin/main"
MODE="branch"

while [ $# -gt 0 ]; do
  case "$1" in
    --staged)  MODE="staged"; shift ;;
    --base)    BASE="${2:?--base needs a ref}"; shift 2 ;;
    -)         MODE="stdin"; shift ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *)         echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  stdin)  cat ;;
  staged) git diff --cached ;;
  branch) git diff "$(git merge-base "$BASE" HEAD 2>/dev/null || echo "$BASE")"...HEAD ;;
esac | RATIO="$RATIO" FIXED="$FIXED" /usr/bin/python3 -c '
import os, re, sys

RATIO = float(os.environ.get("RATIO", "1.2"))
FIXED = float(os.environ.get("FIXED", "220"))

# Only hand-written source counts. Generated, vendored and prose files would
# inflate the prod side and hide real test debt behind a large mechanical diff.
SRC     = (".py", ".ts", ".tsx", ".js", ".jsx", ".go")
SKIP    = ("/vendor/", "/node_modules/", "/migrations/", ".pb.go", "_pb2.py",
           ".generated.", "lock.json", "package-lock", "uv.lock")
TEST_DIR = ("/tests/", "/test/", "/__tests__/", "/e2e/")
TEST_SFX = ("_test.py", ".test.ts", ".test.tsx", ".test.js", ".test.jsx",
            ".spec.ts", ".spec.tsx", ".spec.js")
TEST_FN  = re.compile(r"^\s*(?:async\s+)?def\s+test_|^\s*(?:it|test)(?:\.each\([^)]*\))?\s*\(")

def is_test(p):
    b = os.path.basename(p)
    return (any(d in p for d in TEST_DIR) or b.startswith("test_")
            or b.endswith(TEST_SFX))

path, test_loc, prod_loc, test_fns = None, 0, 0, 0

for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line.startswith("+++ "):
        p = line[4:].strip()
        path = None if p == "/dev/null" else re.sub(r"^b/", "", p)
        continue
    if not path or not line.startswith("+") or line.startswith("+++"):
        continue
    if not path.endswith(SRC) or any(s in path for s in SKIP):
        continue
    text = line[1:]
    if not text.strip():
        continue
    if is_test(path):
        test_loc += 1
        if TEST_FN.match(text):
            test_fns += 1
    else:
        prod_loc += 1

allowed = FIXED + RATIO * prod_loc
dens = (1000.0 * test_fns / prod_loc) if prod_loc else 0.0

if test_loc <= allowed:
    print("test-discipline: clean (%d test / %d prod added LOC, allowance %d)"
          % (test_loc, prod_loc, round(allowed)))
    sys.exit(0)

print("test-discipline: 1 finding(s)\n")
print("  %d added test LOC against %d added prod LOC" % (test_loc, prod_loc))
print("      %d%% of the allowance (%d = %d + %.1f x prod); %d new test functions, %.1f per 1000 prod LOC"
      % (round(100.0 * test_loc / allowed), round(allowed), round(FIXED), RATIO, test_fns, dens))
print("      test the contract, not the implementation — delete tests that pin module")
print("      structure, exact internal call arguments, or library behaviour covered elsewhere\n")
print("Allowance is affine, not a ratio: %d lines of fixed scaffolding plus %.1f" % (round(FIXED), RATIO))
print("per added prod line. Over it, name the contract each extra test pins, or cut it.")
sys.exit(1)
'
