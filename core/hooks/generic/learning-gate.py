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

Both paths log NEW `[learnings-<file>.md#<N>]` citations and bump per-entry
counts under ${HARNESS_METRICS:-~/.agent-knowledge/metrics} so consolidation can
prune by actual usage.

Config (env):
  LEARN_GATE_DISABLE=1     -> no gating/nudging (logging still runs)
  LEARN_METRICS_DISABLE=1  -> no citation logging
  LEARN_TOOLUSE_MIN  (default 8)  -> tool-use count that counts as "substantive"
  LEARN_MAIN_GAP     (default 2)  -> work-minus-persist gap that triggers the soft nudge
  HARNESS_METRICS                 -> metrics dir (default ~/.agent-knowledge/metrics)

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
CIT_LOG = os.path.join(METRICS_DIR, "learning-citations.jsonl")
USAGE_JSON = os.path.join(METRICS_DIR, "learning-usage.json")
CIT_RE = re.compile(r"learnings-[\w.\-]+\.md#\d+")
TMP = "/tmp"


def _envint(name, default):
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


def parse_transcript(path):
    """Single pass: tally tool use, mutations, persistence, and citations."""
    tool_uses = mutations = commits_prs = bd_remembers = learnings_writes = 0
    citations = []
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
                if name in ("Edit", "Write", "NotebookEdit", "MultiEdit", "Create"):
                    mutations += 1
                    fp = str(inp.get("file_path", ""))
                    # Any recognized knowledge store counts as persistence:
                    # shared learnings files, or a runtime-native project memory file.
                    if (("learnings-" in fp and fp.endswith(".md"))
                            or ("/memory/" in fp and fp.endswith(".md"))):
                        learnings_writes += 1
                elif name in ("Bash", "Execute"):
                    cmd = str(inp.get("command", ""))
                    # `learn.sh` wraps `bd remember`, so match it too.
                    if ("bd remember" in cmd or "bd comments add" in cmd
                            or "learn.sh" in cmd):
                        bd_remembers += 1
                    if re.search(r"\bgit commit\b", cmd) or "gh pr create" in cmd:
                        commits_prs += 1
    return {
        "tool_uses": tool_uses, "mutations": mutations, "commits_prs": commits_prs,
        "bd_remembers": bd_remembers, "learnings_writes": learnings_writes,
        "citations": citations,
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
        handle_subagent_stop(data, stats)
    elif event == "UserPromptSubmit":
        log_new_citations(path, stats["citations"], "main")
        handle_main_prompt(data, path, stats)
    sys.exit(0)


if __name__ == "__main__":
    main()
