#!/usr/bin/env python3
"""
PreCompact hook: persist bd memories before context compression.

Reads the session transcript, extracts structured data from recent assistant
messages (PR numbers, bd task IDs, generic ticket keys, key actions), and
stores a condensed snapshot as a bd memory plus a pre-compact comment on
each in-progress task.

This file is intentionally generic — no organisation-specific cluster names,
ticket prefixes, or project keywords are hard-coded. Override the
`TICKET_KEY_RE` and `BD_TASK_RE` patterns via environment variables if your
repo uses different conventions.

bd discovers its database from the working directory, so every bd command is
run from the directory that owns `.beads/` — located by walking up from the
runtime-provided cwd / workspace and the transcript path (or `$BEADS_DIR`).
No paths are hard-coded; if none is found the hook degrades to a plain
`bd sync` from the current directory.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

# Match generic ticket keys like ABC-1234, PROJ-42, etc. Override with
# AGENT_HARNESS_TICKET_RE for stricter or different formats.
TICKET_KEY_RE = re.compile(
    os.environ.get("AGENT_HARNESS_TICKET_RE", r"\b([A-Z][A-Z0-9]{1,9}-\d{2,6})\b")
)

# bd task IDs default to <prefix>-<alnum>. Override with AGENT_HARNESS_BD_RE.
BD_TASK_RE = re.compile(
    os.environ.get("AGENT_HARNESS_BD_RE", r"\b([a-z][a-z0-9-]{0,12}-[a-z0-9]{2,8})\b")
)

PR_RE = re.compile(r"(?:PR\s*#?|pull/)(\d{2,6})")


def run_cmd(cmd, timeout=10, cwd=None):
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout, cwd=cwd
        )
        return result.returncode == 0, result.stdout.strip()
    except (subprocess.TimeoutExpired, Exception):
        return False, ""


def find_bd_cwd(input_data, transcript_path):
    """Locate the directory that owns `.beads/` by walking up from runtime-
    provided paths. Returns None if no candidate contains a `.beads/` dir — no
    organisation-specific fallback path is ever assumed."""
    candidates = []

    env_dir = os.environ.get("BEADS_DIR")
    if env_dir:
        candidates.append(Path(os.path.expanduser(env_dir)))

    for key in ("cwd", "workspace", "repoPath", "repo_path"):
        value = input_data.get(key)
        if isinstance(value, str) and value:
            candidates.append(Path(os.path.expanduser(value)))

    candidates.append(Path.cwd())

    if transcript_path:
        candidates.append(Path(os.path.expanduser(transcript_path)).parent)

    checked = set()
    for candidate in candidates:
        try:
            current = (candidate if candidate.is_dir() else candidate.parent).resolve()
        except Exception:
            continue
        for path in [current, *current.parents]:
            if path in checked:
                continue
            checked.add(path)
            if (path / ".beads").is_dir():
                return str(path)
    return None


def extract_from_messages(messages):
    text = "\n".join(messages)
    prs = sorted(set(PR_RE.findall(text)))
    bd_tasks = sorted({m for m in BD_TASK_RE.findall(text) if "-" in m})
    tickets = sorted(set(TICKET_KEY_RE.findall(text)))

    actions = []
    patterns = [
        r"(?:created|merged|opened|closed|enabled|disabled|deployed|fixed|updated|added|removed)\s+.{10,80}",
        r"PR\s*#\d+[^.]{0,80}",
    ]
    for pat in patterns:
        for m in re.finditer(pat, text, re.IGNORECASE):
            action = m.group(0).strip().rstrip(",;")
            if len(action) > 15:
                actions.append(action)

    seen = set()
    unique_actions = []
    for a in actions:
        key = a[:40].lower()
        if key not in seen:
            seen.add(key)
            unique_actions.append(a)

    return {
        "prs": prs,
        "bd_tasks": bd_tasks,
        "tickets": tickets,
        "actions": unique_actions[:10],
    }


def parse_transcript(transcript_path):
    messages = []
    try:
        with open(transcript_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if entry.get("role", "") != "assistant":
                    continue
                content = entry.get("content", "")
                if isinstance(content, list):
                    parts = []
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "text":
                            parts.append(block.get("text", ""))
                    content = "\n".join(parts)
                if isinstance(content, str) and len(content) > 20:
                    messages.append(content)
    except Exception:
        return []
    return messages[-20:]


def build_memory(extracted):
    parts = ["Pre-compact session snapshot."]
    if extracted["actions"]:
        parts.append("Actions: " + "; ".join(extracted["actions"][:5]))
    if extracted["prs"]:
        parts.append("PRs: " + ", ".join(f"#{p}" for p in extracted["prs"][:10]))
    if extracted["bd_tasks"]:
        parts.append("bd tasks: " + ", ".join(extracted["bd_tasks"][:10]))
    if extracted["tickets"]:
        parts.append("Tickets: " + ", ".join(extracted["tickets"][:5]))
    memory = " | ".join(parts)
    if len(memory) > 500:
        memory = memory[:497] + "..."
    return memory


def snapshot_in_progress_tasks(memory, cwd=None):
    ok, output = run_cmd(
        "bd list --status in_progress --json 2>/dev/null", timeout=10, cwd=cwd
    )
    if not ok or not output:
        return
    try:
        tasks = json.loads(output)
    except (json.JSONDecodeError, TypeError):
        tasks = [{"id": tid} for tid in BD_TASK_RE.findall(output)]
    for task in tasks:
        task_id = task.get("id", "") if isinstance(task, dict) else ""
        if not task_id:
            continue
        comment = f"Pre-compact snapshot: {memory}"
        safe_comment = comment.replace("'", "'\\''")
        run_cmd(f"bd comments add {task_id} '{safe_comment}'", timeout=10, cwd=cwd)


def main() -> int:
    input_data = {}
    try:
        input_data = json.load(sys.stdin)
    except (json.JSONDecodeError, Exception):
        pass

    transcript_path = os.path.expanduser(input_data.get("transcript_path", ""))
    cwd = find_bd_cwd(input_data, transcript_path)

    if not transcript_path or not Path(transcript_path).is_file():
        run_cmd("bd sync 2>/dev/null", cwd=cwd)
        return 0

    messages = parse_transcript(transcript_path)
    if not messages:
        run_cmd("bd sync 2>/dev/null", cwd=cwd)
        return 0

    extracted = extract_from_messages(messages)
    if not any(extracted.values()):
        run_cmd("bd sync 2>/dev/null", cwd=cwd)
        return 0

    memory = build_memory(extracted)
    safe_memory = memory.replace('"', '\\"').replace("'", "'\\''")
    run_cmd(f"bd remember '{safe_memory}' --key session/pre-compact", timeout=10, cwd=cwd)

    snapshot_in_progress_tasks(memory, cwd)
    run_cmd("bd sync 2>/dev/null", timeout=10, cwd=cwd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
