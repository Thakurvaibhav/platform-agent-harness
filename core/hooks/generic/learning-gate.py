#!/usr/bin/env python3
"""
Learning-capture enforcement + measurement (portable hook).

Wired to two events (names follow the Claude-Code convention; map them to your
runtime's equivalents — see core/hooks/README.md):

  * SubagentStop     -> HARD gate. If a sub-agent did substantive work but
                        persisted nothing, block its stop exactly once and tell
                        it to `bd remember` / `learn.sh` (or explicitly say
                        nothing was non-obvious). A `stop_hook_active`-style
                        flag guards against blocking loops.
  * UserPromptSubmit -> SOFT nudge for the long-lived MAIN session. If work has
                        outpaced persistence since the last nudge, inject a
                        one-line reminder (never blocks). Main-session citations
                        are also logged here.

Both paths record two usage signals under ${HARNESS_METRICS:-~/.agent-knowledge/metrics}:
  * READ frequency (primary) -- per-file counts in learning-reads.json whenever a
    learnings-*.md file is Read. Reads are the truer usage proxy.
  * CITATIONS (secondary) -- per-entry `[learnings-<file>.md#<N>]` counts in
    learning-usage.json when an agent cites an entry.
Consolidation uses these ONLY for ranking and gap-detection -- NEVER to prune or
archive learnings (recall >> precision; a rarely-read entry may hold a critical
once-a-year gotcha). See templates/commands/consolidate.md.

Config (env):
  LEARN_GATE_DISABLE=1     -> no gating/nudging (logging still runs)
  LEARN_METRICS_DISABLE=1  -> no citation/read logging
  LEARN_TOOLUSE_MIN  (default 8)  -> tool-use count that counts as "substantive"
  LEARN_MAIN_GAP     (default 2)  -> work-minus-persist gap that triggers the soft nudge
  HARNESS_METRICS                 -> metrics dir (default ~/.agent-knowledge/metrics)
  HARNESS_REFS                    -> learnings dir (default ~/.agent-knowledge/references)
  HARNESS_ORGS                    -> org tier dir (default ~/.agent-knowledge/orgs)

PORTABILITY NOTE: this parser targets Claude-Code-style JSONL transcripts
(one JSON object per line; assistant turns carry message.content[] blocks with
`type` in {"text","tool_use"}). Other runtimes shape their transcripts
differently — the parser is written defensively (skips unparseable lines,
tolerates missing keys) but you may need a small tweak to `parse_transcript`
(e.g. different role/content field names) for your runtime. Stdlib only.
"""
import hashlib
import json
import os
import re
import sys

METRICS_DIR = os.environ.get(
    "HARNESS_METRICS", os.path.expanduser("~/.agent-knowledge/metrics")
)
REFS_DIR = os.environ.get(
    "HARNESS_REFS", os.path.expanduser("~/.agent-knowledge/references")
)
# Optional per-organization knowledge tier: `orgs/<org>/<file>.md`. Dormant
# until such a directory exists — the predicates below simply never match.
ORGS_DIR = os.environ.get(
    "HARNESS_ORGS", os.path.expanduser("~/.agent-knowledge/orgs")
)
CIT_LOG = os.path.join(METRICS_DIR, "learning-citations.jsonl")
USAGE_JSON = os.path.join(METRICS_DIR, "learning-usage.json")
READS_JSON = os.path.join(METRICS_DIR, "learning-reads.json")
READS_LOG = os.path.join(METRICS_DIR, "learning-reads.jsonl")
CIT_RE = re.compile(r"(?:orgs/[\w.\-]+/[\w.\-]+|learnings-[\w.\-]+)\.md#P?\d+[a-z]?")
LEARN_FILE_RE = re.compile(r"learnings-[\w.\-]+\.md")
# Org files live outside REFS_DIR without the `learnings-` prefix. Match only in
# PATH-QUALIFIED form: bare `istio.md` would match half the markdown in a repo.
ORG_FILE_RE = re.compile(r"orgs/[\w.\-]+/[\w.\-]+\.md")
# A search *for* a filename is not a read of it: `grep 'learnings-foo.md' *.md`
# looks for the name inside other files, and counting it ranks phantoms.
SEARCH_RE = re.compile(r"\b(?:grep|rg|ag|ack|fgrep|egrep)\b")
QUOTED_RE = re.compile(r"""'[^']*'|"[^"]*\"""")
TMP = "/tmp"


def _envint(name, default):
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


def is_real_learnings_file(name, path=""):
    """Outcome check: the referenced learnings file must actually EXIST.

    A `Read` tool_use is emitted even when the read FAILED because the file was
    not there, so counting the intent credits reads that never happened. Prefer
    the literal path the agent used — layouts differ (in-repo
    `agent-knowledge/references/` vs the `$HARNESS_REFS` home) — and fall back to
    REFS_DIR for the bare names extracted from a shell command.
    """
    if path and os.path.isfile(os.path.expanduser(path)):
        return True
    return bool(name) and os.path.isfile(os.path.join(REFS_DIR, os.path.basename(name)))


def is_real_org_file(rel, path=""):
    """Same outcome check for the org tier: `orgs/<org>/<file>.md` must exist."""
    if path and os.path.isfile(os.path.expanduser(path)):
        return True
    return bool(rel) and os.path.isfile(
        os.path.join(ORGS_DIR, rel.split("orgs/", 1)[-1])
    )


def org_key(rel):
    """Metrics key for an org file: `orgs/<org>/<file>.md`, NOT the basename.

    Org files deliberately share basenames ACROSS organizations
    (`orgs/org-a/istio.md` vs `orgs/org-b/istio.md`), so a basename key would
    merge two organizations' read counts into one meaningless number.
    """
    return "orgs/" + rel.split("orgs/", 1)[-1]


def learnings_reads_in_cmd(cmd):
    """Learnings files READ by a shell command, excluding search patterns and phantoms."""
    quoted = [m.span() for m in QUOTED_RE.finditer(cmd)] if SEARCH_RE.search(cmd) else []
    out = []
    for m in LEARN_FILE_RE.finditer(cmd):
        if any(qs < m.start() < qe for qs, qe in quoted):
            continue  # inside a search pattern, not a path being read
        if is_real_learnings_file(m.group(0)):
            out.append(m.group(0))
    for m in ORG_FILE_RE.finditer(cmd):
        if any(qs < m.start() < qe for qs, qe in quoted):
            continue
        if is_real_org_file(m.group(0)):
            out.append(org_key(m.group(0)))
    return out


def parse_transcript(path):
    """Single pass: tally tool use, mutations, persistence, citations, and reads."""
    tool_uses = mutations = commits_prs = bd_remembers = learnings_writes = 0
    citations = []
    learnings_reads = []  # files read (for read-frequency tracking)
    try:
        with open(path) as f:
            lines = f.readlines()
    except OSError:
        return None
    for line in lines:
        try:
            o = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if not isinstance(o, dict) or o.get("type") != "assistant":
            continue
        content = o.get("message", {}).get("content", []) if isinstance(o.get("message"), dict) else []
        if not isinstance(content, list):
            continue
        for b in content:
            if not isinstance(b, dict):
                continue
            bt = b.get("type")
            if bt == "text":
                citations.extend(CIT_RE.findall(b.get("text", "")))
            elif bt == "tool_use":
                tool_uses += 1
                name = b.get("name", "")
                inp = b.get("input", {}) if isinstance(b.get("input"), dict) else {}
                if name == "Read":
                    fp = str(inp.get("file_path", ""))
                    base = os.path.basename(fp)
                    if (base.startswith("learnings-") and base.endswith(".md")
                            and is_real_learnings_file(base, fp)):
                        learnings_reads.append(base)
                    else:
                        om = ORG_FILE_RE.search(fp)
                        if om and is_real_org_file(om.group(0), fp):
                            learnings_reads.append(org_key(om.group(0)))
                elif name in ("Edit", "Write", "NotebookEdit", "MultiEdit", "Create"):
                    mutations += 1
                    fp = str(inp.get("file_path", ""))
                    # Any recognized knowledge store counts as persistence:
                    # shared learnings files, the org tier, or a runtime-native
                    # project memory file. Writing an org file IS capture.
                    if (("learnings-" in fp and fp.endswith(".md"))
                            or (ORG_FILE_RE.search(fp) and fp.endswith(".md"))
                            or ("/memory/" in fp and fp.endswith(".md"))):
                        learnings_writes += 1
                elif name in ("Bash", "Execute"):
                    cmd = str(inp.get("command", ""))
                    # `learn.sh` wraps `bd remember`, so match it too.
                    is_persist = ("bd remember" in cmd or "bd comments add" in cmd
                                  or "learn.sh" in cmd)
                    if is_persist:
                        bd_remembers += 1
                    if re.search(r"\bgit commit\b", cmd) or "gh pr create" in cmd:
                        commits_prs += 1
                    # Shell reads (cat/less/awk/...), per file. Skip persist commands:
                    # a `bd remember` body QUOTES a filename as a citation, not a read.
                    if not is_persist:
                        learnings_reads.extend(learnings_reads_in_cmd(cmd))
    return {
        "tool_uses": tool_uses, "mutations": mutations, "commits_prs": commits_prs,
        "bd_remembers": bd_remembers, "learnings_writes": learnings_writes,
        "citations": citations, "learnings_reads": learnings_reads,
    }


def log_new_citations(path, citations, source):
    """Log only citations not yet logged for this transcript (dedupe on growth)."""
    if os.environ.get("LEARN_METRICS_DISABLE") == "1" or not citations:
        return
    h = hashlib.sha1(path.encode()).hexdigest()[:12]
    marker = os.path.join(TMP, f"learn-cited-{h}.json")
    already = 0
    try:
        with open(marker) as f:
            already = int(json.load(f).get("n", 0))
    except (OSError, json.JSONDecodeError, ValueError):
        pass
    new = citations[already:]
    if not new:
        return
    try:
        os.makedirs(METRICS_DIR, exist_ok=True)
        with open(CIT_LOG, "a") as f:
            for c in new:
                f.write(json.dumps({"cite": c, "source": source,
                                    "transcript": os.path.basename(path)}) + "\n")
        usage = {}
        try:
            with open(USAGE_JSON) as f:
                usage = json.load(f)
        except (OSError, json.JSONDecodeError):
            usage = {}
        if not isinstance(usage, dict):
            usage = {}
        for c in new:
            usage[c] = int(usage.get(c, 0)) + 1
        with open(USAGE_JSON, "w") as f:
            json.dump(usage, f, indent=2, sort_keys=True)
        with open(marker, "w") as f:
            json.dump({"n": len(citations)}, f)
    except OSError:
        pass


def log_learnings_reads(path, reads, source):
    """Log per-file read counts for read-frequency tracking (primary usage signal)."""
    if os.environ.get("LEARN_METRICS_DISABLE") == "1" or not reads:
        return
    h = hashlib.sha1(path.encode()).hexdigest()[:12]
    marker = os.path.join(TMP, f"learn-reads-{h}.json")
    already = 0
    try:
        with open(marker) as f:
            already = int(json.load(f).get("n", 0))
    except (OSError, json.JSONDecodeError, ValueError):
        pass
    new = reads[already:]
    if not new:
        return
    try:
        os.makedirs(METRICS_DIR, exist_ok=True)
        with open(READS_LOG, "a") as f:
            for r in new:
                f.write(json.dumps({"file": r, "source": source,
                                    "transcript": os.path.basename(path)}) + "\n")
        usage = {}
        try:
            with open(READS_JSON) as f:
                usage = json.load(f)
        except (OSError, json.JSONDecodeError):
            usage = {}
        if not isinstance(usage, dict):
            usage = {}
        for r in new:
            usage[r] = int(usage.get(r, 0)) + 1
        with open(READS_JSON, "w") as f:
            json.dump(usage, f, indent=2, sort_keys=True)
        with open(marker, "w") as f:
            json.dump({"n": len(reads)}, f)
    except OSError:
        pass


def handle_subagent_stop(data, stats):
    """Hard gate: block once if substantive work was done but nothing persisted."""
    if os.environ.get("LEARN_GATE_DISABLE") == "1":
        return
    if data.get("stop_hook_active"):   # we already blocked once -> let it stop
        return
    persisted = stats["bd_remembers"] > 0 or stats["learnings_writes"] > 0
    substantive = (stats["mutations"] > 0 or stats["commits_prs"] > 0
                   or stats["tool_uses"] >= _envint("LEARN_TOOLUSE_MIN", 8))
    if substantive and not persisted:
        reason = (
            f"You completed substantive work ({stats['mutations']} file edit(s), "
            f"{stats['commits_prs']} commit/PR action(s), {stats['tool_uses']} tool call(s)) "
            "but recorded no learning. Per the Learning Capture Protocol: if you discovered "
            "anything non-obvious — a gotcha, a non-obvious fix, or a decision and its "
            "rationale that would save a future agent real time and is not already in "
            "learnings — persist it NOW with `agent-knowledge/scripts/learn.sh \"<insight>\" "
            "<domain>/<category>/<topic>` (or `bd remember`, or append to the matching "
            "agent-knowledge/references/learnings-*.md). If nothing was genuinely "
            "non-obvious, state that explicitly in one line, then finish."
        )
        print(json.dumps({"decision": "block", "reason": reason}))


def handle_main_prompt(data, path, stats):
    """Soft, debounced reminder for the long-lived main session."""
    if os.environ.get("LEARN_GATE_DISABLE") == "1":
        return
    session_id = data.get("session_id", "")
    if not session_id:
        return
    marker = os.path.join(TMP, f"learn-main-{session_id}.json")
    last_mut = 0
    try:
        with open(marker) as f:
            last_mut = int(json.load(f).get("mut", 0))
    except (OSError, json.JSONDecodeError, ValueError):
        pass
    work = stats["mutations"] + stats["commits_prs"]
    persist = stats["bd_remembers"] + stats["learnings_writes"]
    gap = _envint("LEARN_MAIN_GAP", 2)
    # New work since last nudge, and persistence is lagging by a margin.
    if work > last_mut and (work - persist) >= gap:
        try:
            with open(marker, "w") as f:
                json.dump({"mut": work}, f)
        except OSError:
            pass
        msg = ("[learning-capture] Recent direct work hasn't been persisted. If anything "
               "non-obvious came up, jot it now: `agent-knowledge/scripts/learn.sh "
               "\"<insight>\" <domain>/<category>/<topic>` (or `bd remember`) — don't batch "
               "it to task end.")
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit", "additionalContext": msg}}))


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)
    if not isinstance(data, dict):
        sys.exit(0)
    path = data.get("transcript_path", "")
    if not path or not os.path.isfile(path):
        sys.exit(0)
    stats = parse_transcript(path)
    if stats is None:
        sys.exit(0)

    event = data.get("hook_event_name", "")
    if event == "SubagentStop":
        log_new_citations(path, stats["citations"], "subagent")
        log_learnings_reads(path, stats["learnings_reads"], "subagent")
        handle_subagent_stop(data, stats)
    elif event == "UserPromptSubmit":
        log_new_citations(path, stats["citations"], "main")
        log_learnings_reads(path, stats["learnings_reads"], "main")
        handle_main_prompt(data, path, stats)
    sys.exit(0)


if __name__ == "__main__":
    main()
