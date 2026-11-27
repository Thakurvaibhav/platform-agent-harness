#!/usr/bin/env python3
"""drift-check.sh: detect staleness in the knowledge harness.

Run at session start/resume. Warns about:
  FRESHNESS:
  1. Stale graphify graph (>7 days behind latest commit)
  2. Learnings files not updated despite recent repo activity
  3. bd memory bloat
  4. Consolidation overdue (>7 days)
  CONSISTENCY (cross-reference integrity, not just age):
  5. Learnings file exists but is not indexed in index.md (discovery gap)
  6. index.md references a learnings file that does not exist (dangling)
  7. Asymmetric cross-ref: A's "See also:" lists B, but B does not list A back
  7b. Instance tier: an org file's "See also:" points at a file that does not exist
  8. An engineering agent that does not route to the code-quality standard

Exit codes: 0 = clean, 1 = warnings found (non-blocking).

This is a Python program. The .sh name is kept deliberately: the protocol files,
index.md and the consolidation workflow all reference this exact path, and
renaming it is where all the risk lives.

Interpreter: /usr/bin/env python3, not a pinned path. This script is run
interactively, never from a hook with a stripped PATH, so a missing interpreter
fails loudly instead of silently. The code needs nothing past 3.9. Using os.stat
also retires the `/usr/bin/stat -f %m` call the shell version used, which was
BSD-only and so reported every file as age 0 on Linux.

Estate paths are not in this file. WORK_ROOT and BEADS_DB come from env.sh, which
reads them from the gitignored config.sh.
"""

import glob
import os
import re
import subprocess
import sys
import time
from datetime import datetime

HOME = os.path.expanduser("~")
# Resolved relative to this script first, so a checkout in any location checks
# itself; the deployed default is the fallback.
_SELF_HOME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HARNESS_HOME = (os.environ.get("HARNESS_HOME")
                or (_SELF_HOME if os.path.isdir(os.path.join(_SELF_HOME, "references"))
                    else os.path.join(HOME, ".agent-knowledge")))
ENV_SH = os.path.join(HARNESS_HOME, "env.sh")
HARNESS_VARS = ("WORK_ROOT", "BEADS_DB", "HARNESS_DOCS", "ACTIVE_ORG")

# Directory holding the runtime's agent definitions. Runtime-specific, so it is an
# env var: an adopter on another runtime points it at their own agent directory.
AGENTS_DIR = os.environ.get("HARNESS_AGENTS") or os.path.join(HOME, ".claude", "agents")
MAIN_INSTRUCTIONS = os.environ.get("HARNESS_INSTRUCTIONS") or os.path.join(HOME, ".claude", "AGENTS.md")

LEARN_REF_RE = re.compile(r"learnings-[a-z0-9-]+\.md")
SEE_ALSO_RE = re.compile(r"see also:", re.I)
DATE_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")

WARNINGS = []
REFS_DIR = ""
BD_DIR = ""
WORK_ROOT = ""


def load_harness_env():
    """Hooks and cron do not reliably source the login shell, and a Python entry
    point cannot source a shell file, so ask a shell what env.sh would set."""
    missing = [v for v in HARNESS_VARS if v not in os.environ]
    if not missing or not os.path.isfile(ENV_SH):
        return
    script = '. "%s" >/dev/null 2>&1; ' % ENV_SH
    script += "; ".join('printf "%%s\\n" "${%s-}"' % v for v in missing)
    try:
        raw = subprocess.check_output(["/bin/sh", "-c", script], stderr=subprocess.DEVNULL)
    except Exception:
        return
    values = raw.decode("utf-8", "replace").split("\n")
    for name, value in zip(missing, values):
        os.environ[name] = value


def posix_dirname(path):
    # `dirname ""` prints ".", and the shell version relied on that to fall back to
    # the current directory. os.path.dirname returns "", which would make every bd
    # call fail with a bad cwd and report the hive as unmeasurable.
    return os.path.dirname(path) or "."


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def file_mtime(path):
    try:
        return int(os.stat(path).st_mtime)
    except OSError:
        return 0


def first_see_also(path):
    for line in read_text(path).splitlines():
        if SEE_ALSO_RE.search(line):
            return line
    return ""


def learnings_files(directory):
    return [f for f in sorted(glob.glob(os.path.join(directory, "learnings-*.md")))
            if os.path.isfile(f)]


def env_int(name, default):
    raw = os.environ.get(name) or ""
    try:
        return int(raw)
    except ValueError:
        return default


# --- 1. Graphify freshness ---
def check_graph_freshness(repo_dir):
    repo_name = os.path.basename(repo_dir)
    graph = os.path.join(repo_dir, "graphify-out", "graph.json")

    if not os.path.isfile(graph):
        WARNINGS.append("DRIFT: %s has no graphify graph (graphify-out/graph.json missing)"
                        % repo_name)
        return

    graph_mtime = file_mtime(graph)
    graph_age_days = (int(time.time()) - graph_mtime) // 86400

    if graph_age_days > 7:
        try:
            out = subprocess.check_output(
                ["git", "log", "--oneline", "--since=@%d" % graph_mtime],
                cwd=repo_dir, stderr=subprocess.DEVNULL)
            commits_since = len(out.splitlines())
        except Exception:
            commits_since = 0
        if commits_since > 5:
            WARNINGS.append(
                "DRIFT: %s graph is %dd old with %d commits since last build. "
                "Run: cd %s && graphify . --update"
                % (repo_name, graph_age_days, commits_since, repo_dir))


# --- 2. Learnings staleness ---
def check_learnings_freshness():
    if not os.path.isdir(REFS_DIR):
        return

    oldest_file = ""
    oldest_days = 0
    now = int(time.time())

    for f in learnings_files(REFS_DIR):
        age_days = (now - file_mtime(f)) // 86400
        if age_days > oldest_days:
            oldest_days = age_days
            oldest_file = os.path.basename(f)

    # mtime is a weak staleness proxy: a correct, stable file needs no edits. Only
    # flag genuine abandonment, so this stays signal rather than a recurring warning.
    if oldest_days > 120:
        WARNINGS.append("DRIFT: %s not updated in %dd, check it is still accurate"
                        % (oldest_file, oldest_days))


# --- 3. Memory bloat ---
def bd_memory_count():
    # Count from --json, NOT by grepping the human-readable output. A `grep -c` on a
    # formatted surface silently returns 0 after a format change, and a counter that
    # can only under-report reads as good news (learnings-agent-workflow.md#64).
    try:
        import json
        out = subprocess.check_output(["bd", "memories", "--json"], cwd=BD_DIR,
                                      stderr=subprocess.DEVNULL)
        data = json.loads(out.decode("utf-8", "replace"))
    except Exception:
        return -1
    return len(data) if isinstance(data, (dict, list)) else 0


def check_memory_count():
    count = bd_memory_count()
    # -1 means the count itself failed. Say so rather than passing silently.
    if count < 0:
        WARNINGS.append("DRIFT: bd memory count UNAVAILABLE (bd memories --json failed) "
                        "(bloat check did not run)")
        return
    # An ESCALATION, not the routine trigger: check_consolidation_freshness owns that
    # (>7 days). At an observed write rate of ~34/day a threshold of 60 fired on day
    # two and stayed on, and a warning that is true most of the time trains the reader
    # to skip the whole report. Retune this to your own write rate.
    if count > env_int("BD_MEMORY_THRESHOLD", 300):
        WARNINGS.append("DRIFT: %d bd memories, above the weekly cadence. "
                        "Run /consolidate now, do not wait for the 7-day mark" % count)


# --- 4. Consolidation overdue ---
def last_consolidation_date():
    # Anchor to the canonical `meta/last-consolidation` memory: `bd memories
    # consolidation` fuzzy-matches ANY memory containing "consolidation", so taking
    # the first date anywhere in the output grabs one from an unrelated memory.
    try:
        out = subprocess.check_output(["bd", "memories", "consolidation"], cwd=BD_DIR,
                                      stderr=subprocess.DEVNULL)
    except Exception:
        return ""
    lines = out.decode("utf-8", "replace").splitlines()
    keep = set()
    for i, line in enumerate(lines):
        if "meta/last-consolidation" in line:
            keep.add(i)
            keep.add(i + 1)
    for i in sorted(keep):
        if i < len(lines):
            match = DATE_RE.search(lines[i])
            if match:
                return match.group(0)
    return ""


def check_consolidation_freshness():
    last_consol = last_consolidation_date()
    if not last_consol:
        WARNINGS.append("DRIFT: No consolidation ever recorded. Run /consolidate")
        return

    try:
        consol_epoch = int(datetime.strptime(last_consol, "%Y-%m-%d").timestamp())
    except Exception:
        consol_epoch = 0
    days_since = (int(time.time()) - consol_epoch) // 86400

    if days_since > 7:
        WARNINGS.append("DRIFT: Last consolidation was %dd ago (%s). Consider /consolidate"
                        % (days_since, last_consol))


# --- 5-7. Reference consistency (index integrity + cross-ref symmetry) ---
def check_reference_consistency():
    index = os.path.join(REFS_DIR, "index.md")
    if not os.path.isfile(index):
        WARNINGS.append("DRIFT: index.md missing at %s" % index)
        return
    index_text = read_text(index)
    files = learnings_files(REFS_DIR)

    # 5. Every learnings-*.md on disk is referenced in index.md
    for f in files:
        base = os.path.basename(f)
        if base not in index_text:
            WARNINGS.append("DRIFT: %s exists but is not indexed in index.md (discovery gap)"
                            % base)

    # 6. Every learnings-*.md named in index.md exists on disk
    for ref in sorted(set(LEARN_REF_RE.findall(index_text))):
        if not os.path.isfile(os.path.join(REFS_DIR, ref)):
            WARNINGS.append("DRIFT: index.md references %s but the file does not exist "
                            "(dangling)" % ref)

    # 7. "See also:" cross-ref symmetry: if A lists B, B should list A
    for f in files:
        a = os.path.basename(f)
        seealso = first_see_also(f)
        if not seealso:
            continue
        for b in sorted(set(LEARN_REF_RE.findall(seealso))):
            if b == a:
                continue
            # A See-also pointing at a file that does not exist used to be skipped
            # here, so a rename or deletion left dead cross-refs that nothing caught.
            if not os.path.isfile(os.path.join(REFS_DIR, b)):
                WARNINGS.append("DRIFT: %s 'See also:' references %s but the file does "
                                "not exist" % (a, b))
                continue
            if a not in first_see_also(os.path.join(REFS_DIR, b)):
                WARNINGS.append("DRIFT: cross-ref asymmetry: %s lists %s, but %s's "
                                "'See also:' omits %s" % (a, b, b, a))

    # 7b. Same dangling check for the instance tier. Symmetry is not expected there
    # (an org file points at its portable twin, not the reverse), but a pointer to a
    # file that no longer exists is just as dead.
    orgs_dir = os.environ.get("HARNESS_ORGS") or os.path.join(os.path.dirname(REFS_DIR), "orgs")
    for o in sorted(glob.glob(os.path.join(orgs_dir, "*", "*.md"))):
        if not os.path.isfile(o):
            continue
        oa = "orgs/%s/%s" % (os.path.basename(os.path.dirname(o)), os.path.basename(o))
        oline = first_see_also(o)
        if not oline:
            continue
        for t in sorted(set(LEARN_REF_RE.findall(oline))):
            if not os.path.isfile(os.path.join(REFS_DIR, t)):
                WARNINGS.append("DRIFT: %s 'See also:' references %s but the file does "
                                "not exist" % (oa, t))


# --- 8. Standard routing ---
def check_standard_routing():
    """Every engineering agent routes to the canonical code-quality standard. A rule
    that never reaches the agent is the most common way standards fail, so the routing
    itself is asserted, not assumed."""
    std = os.path.join(REFS_DIR, "code-quality.md")
    if not os.path.isfile(std):
        # The twin keeps the standard under core/protocols/; a deployed home keeps it
        # beside the learnings. Check both before calling it missing.
        alt = os.path.join(os.path.dirname(HARNESS_HOME), "core", "protocols", "code-quality.md")
        if not os.path.isfile(alt):
            WARNINGS.append("DRIFT: code-quality.md missing at %s" % std)
            return
    if not os.path.isdir(AGENTS_DIR):
        return

    # Read-only / non-engineering agents legitimately skip it.
    skip = ("alert-investigator", "task-planner", "tool-researcher")
    for f in sorted(glob.glob(os.path.join(AGENTS_DIR, "*.md"))):
        if not os.path.isfile(f):
            continue
        base = os.path.basename(f)[:-len(".md")]
        if base in skip:
            continue
        if "code-quality.md" not in read_text(f):
            WARNINGS.append("DRIFT: agent '%s' does not reference code-quality.md "
                            "(standard will not reach it)" % base)

    if os.path.isfile(MAIN_INSTRUCTIONS) and "code-quality.md" not in read_text(MAIN_INSTRUCTIONS):
        WARNINGS.append("DRIFT: main instruction file does not reference code-quality.md")
    dispatch = os.path.join(HARNESS_HOME, "scripts", "codex-dispatch.sh")
    if os.path.isfile(dispatch) and "code-quality.md" not in read_text(dispatch):
        WARNINGS.append("DRIFT: codex-dispatch.sh preamble does not name code-quality.md "
                        "(Codex workers get no standard)")


def main():
    global REFS_DIR, BD_DIR, WORK_ROOT
    # Warning text carries em-dashes, and a C-locale cron would otherwise raise
    # UnicodeEncodeError where the shell version just wrote bytes.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except AttributeError:
        pass

    load_harness_env()
    REFS_DIR = os.environ.get("HARNESS_REFS") or os.path.join(HARNESS_HOME, "references")
    # Directory the bd checks run from; bd discovers the hive from here.
    BD_DIR = posix_dirname(os.environ.get("BEADS_DB", ""))
    WORK_ROOT = os.environ.get("WORK_ROOT", "")

    # Only repos that already carry a graphify-out/: a repo nobody has graphed is not
    # drift, and warning on every un-graphed repo would bury the real signal.
    if WORK_ROOT and os.path.isdir(WORK_ROOT):
        for repo in sorted(glob.glob(os.path.join(WORK_ROOT, "*", ""))):
            if os.path.isdir(os.path.join(repo, "graphify-out")):
                check_graph_freshness(repo.rstrip("/"))

    check_learnings_freshness()
    check_memory_count()
    check_consolidation_freshness()
    check_reference_consistency()
    check_standard_routing()

    if not WARNINGS:
        print("Harness health: all clear")
        return 0
    print("## Harness Drift Warnings (%d)" % len(WARNINGS))
    print("")
    for w in WARNINGS:
        print("- %s" % w)
    return 1


if __name__ == "__main__":
    sys.exit(main())
