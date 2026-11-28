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

The .sh name is load-bearing: the protocol files, index.md and the consolidation
workflow all reference this exact path. Estate paths come from env.sh / config.sh.
"""

import glob
import os
import re
import subprocess
import sys
import time
from datetime import datetime

HOME = os.path.expanduser("~")
# Resolved relative to this script first, so any checkout checks itself.
_SELF_HOME = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HARNESS_HOME = (os.environ.get("HARNESS_HOME")
                or (_SELF_HOME if os.path.isdir(os.path.join(_SELF_HOME, "references"))
                    else os.path.join(HOME, ".agent-knowledge")))
ENV_SH = os.path.join(HARNESS_HOME, "env.sh")
HARNESS_VARS = ("WORK_ROOT", "BEADS_DB", "HARNESS_DOCS", "ACTIVE_ORG")

# Runtime-specific, so an adopter can point it at their own agent directory.
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
    """A Python entry point cannot source a shell file, so ask a shell what env.sh sets."""
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
    # os.path.dirname returns "" where `dirname` prints "."; an empty cwd fails bd.
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

    # mtime is a weak proxy, a stable file needs no edits: flag abandonment only.
    if oldest_days > 120:
        WARNINGS.append("DRIFT: %s not updated in %dd, check it is still accurate"
                        % (oldest_file, oldest_days))


def bd_memory_count():
    # Count from --json: a grep of a formatted surface silently returns 0 on a format change.
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
    if count < 0:
        WARNINGS.append("DRIFT: bd memory count UNAVAILABLE (bd memories --json failed) "
                        "(bloat check did not run)")
        return
    # An ESCALATION, not the routine trigger: one that fires most days gets skipped.
    # Retune to your own write rate.
    if count > env_int("BD_MEMORY_THRESHOLD", 300):
        WARNINGS.append("DRIFT: %d bd memories, above the weekly cadence. "
                        "Run /consolidate now, do not wait for the 7-day mark" % count)


def last_consolidation_date():
    # Anchor to `meta/last-consolidation`: the query fuzzy-matches ANY memory holding
    # "consolidation", so the first date in the output can be an unrelated memory's.
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


def check_reference_consistency():
    index = os.path.join(REFS_DIR, "index.md")
    if not os.path.isfile(index):
        WARNINGS.append("DRIFT: index.md missing at %s" % index)
        return
    index_text = read_text(index)
    files = learnings_files(REFS_DIR)

    for f in files:
        base = os.path.basename(f)
        if base not in index_text:
            WARNINGS.append("DRIFT: %s exists but is not indexed in index.md (discovery gap)"
                            % base)

    for ref in sorted(set(LEARN_REF_RE.findall(index_text))):
        if not os.path.isfile(os.path.join(REFS_DIR, ref)):
            WARNINGS.append("DRIFT: index.md references %s but the file does not exist "
                            "(dangling)" % ref)

    for f in files:
        a = os.path.basename(f)
        seealso = first_see_also(f)
        if not seealso:
            continue
        for b in sorted(set(LEARN_REF_RE.findall(seealso))):
            if b == a:
                continue
            if not os.path.isfile(os.path.join(REFS_DIR, b)):
                WARNINGS.append("DRIFT: %s 'See also:' references %s but the file does "
                                "not exist" % (a, b))
                continue
            if a not in first_see_also(os.path.join(REFS_DIR, b)):
                WARNINGS.append("DRIFT: cross-ref asymmetry: %s lists %s, but %s's "
                                "'See also:' omits %s" % (a, b, b, a))

    # Instance tier: dangling only, since an org file points at its twin one way.
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


def check_standard_routing():
    """Assert the routing itself: a rule that never reaches the agent is the most
    common way a standard fails."""
    std = os.path.join(REFS_DIR, "code-quality.md")
    if not os.path.isfile(std):
    # The twin keeps the standard under core/protocols/, a deployed home beside the
    # learnings: check both before calling it missing.
        alt = os.path.join(os.path.dirname(HARNESS_HOME), "core", "protocols", "code-quality.md")
        if not os.path.isfile(alt):
            WARNINGS.append("DRIFT: code-quality.md missing at %s" % std)
            return
    if not os.path.isdir(AGENTS_DIR):
        return

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
    # Warning text carries em-dashes, which a C-locale cron would otherwise reject.
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except AttributeError:
        pass

    load_harness_env()
    REFS_DIR = os.environ.get("HARNESS_REFS") or os.path.join(HARNESS_HOME, "references")
    BD_DIR = posix_dirname(os.environ.get("BEADS_DB", ""))
    WORK_ROOT = os.environ.get("WORK_ROOT", "")

    # Only repos already carrying a graphify-out/: an ungraphed repo is not drift.
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
