#!/usr/bin/python3
"""Codex Stop hook: learning-capture gate (parity with the generic SubagentStop gate).

Blocks the stop ONCE if the session did substantive work but persisted nothing.
Either capture the insight, or say explicitly there was not one.

POLICY IS SHARED with core/hooks/generic/learning-gate.py: change both together.
Only the transcript adapter below is Codex-specific.
  * substantive = any mutation/commit/PR, OR >= LEARN_TOOLUSE_READONLY tool calls.
  * captured    = `bd remember` / `bd comments add` / `learn.sh`, OR a write to a
                  learnings-*.md or orgs/**.md file.
  * unmeasurable != pass (learnings-agent-workflow.md#64).

Payload (stdin): transcript_path, stop_hook_active (loop guard).
Output: {"continue":true} = allow. {"decision":"block","reason":...} = block once.

DETECTION MUST READ ONLY TOOL-INVOCATION FIELDS (`arguments.cmd`, `input`), never
message, reasoning, or tool-OUTPUT lines. The session-prime hook injects the protocol
text (which literally contains "bd remember ... --key" and every learnings-*.md
filename) into the transcript, so a naive grep sees "captured" in EVERY session and
the gate silently never fires. That bug shipped once; do not reintroduce it.

TRUST CAVEAT: headless `codex exec` SKIPS untrusted hooks. Editing ~/.codex/hooks.json
re-arms the trust prompt: re-trust (run `codex` interactively once) or this is a no-op.

Wiring: a Stop entry in ~/.codex/hooks.json, see adapters/codex-cli/README.md.
Kill switch: LEARN_GATE_DISABLE=1

This is a Python program. The .sh name is kept deliberately: ~/.codex/hooks.json and
the adapter docs reference this exact path, and renaming it is where all the risk
lives. It was Python inside a single-quoted shell heredoc, which is why `bash -n`
passed while the Python itself was never syntax-checked and never testable. The
interpreter stays /usr/bin/python3 because a Stop hook has to run when a package
manager's bin dir is not on PATH, so the code below is 3.9-compatible.
"""

import json
import os
import re
import sys

ALLOW = json.dumps({"continue": True})


def out(s):
    print(s)
    sys.exit(0)


def block(reason):
    # `decision: block` carries the reason back as a continuation prompt. `continue:
    # false` only sets should_stop, which KILLS the turn and feeds the worker nothing
    # (codex-rs/hooks/src/events/stop.rs, rust-v0.153.4).
    out(json.dumps({"decision": "block", "reason": reason}))


def envint(name, default):
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


UNMEASURABLE = (
    "Learning-capture gate: your transcript could not be read, so whether you persisted "
    "anything is unverified, do not read that as a pass. If you discovered anything "
    "non-obvious, run `agent-knowledge/scripts/learn.sh \"<insight>\" "
    "<domain>/<category>/<topic>` now, or state \"No ingestible insight\" with a one-line reason."
)

BLOCKED = (
    "Learning-capture gate: substantive work, nothing persisted. Before stopping, run "
    "`agent-knowledge/scripts/learn.sh \"<insight>\" <domain>/<category>/<topic>` "
    "(or `bd remember ... --key ...`) for each non-obvious finding, or state "
    "\"No ingestible insight\" with a one-line reason. Bar: durable and reusable, "
    "not a restatement of the task."
)

# Redirect arm excludes comparison/arrow operators and fd-dup forms (`2>&1`, `=>`, `->`,
# `>=`, `>/dev/null`); without that it matches most read-only commands and everything
# grades as a mutation. The quote pair in the class used to be spliced in as
# chr(39) + chr(34) because the program lived inside a single-quoted shell string; in a
# real file it is written literally, and the compiled pattern is byte-identical.
MUTATE = re.compile(
    r"""apply_patch|git\s+commit\b|gh\s+pr\s+create|\btee\b|\bsed\s+-i\b"""
    r"""|(?<![-=<>!+*/%&0-9])>>?\s*(?!/dev/null)[~./$\w'"]""", re.I)
CAPTURE = re.compile(r"\bbd\s+remember\b|\bbd\s+comments\s+add\b|learn\.sh", re.I)
KNOWLEDGE = re.compile(r"learnings-[\w.\-]+\.md|orgs/[\w.\-]+/[\w.\-]+\.md")


def main():
    # Byte-for-byte the shell early exit this replaces, which printed the compact form
    # with no space after the colon.
    if os.environ.get("LEARN_GATE_DISABLE", "0") == "1":
        print('{"continue":true}')
        return

    try:
        payload = json.load(sys.stdin)
    except Exception:
        out(ALLOW)

    # Blocked once already this turn, never block twice.
    if payload.get("stop_hook_active"):
        out(ALLOW)

    path = payload.get("transcript_path") or ""
    if not path:
        block(UNMEASURABLE)

    tool_calls = mutated = captured = 0
    declined = False
    seen = parsed = 0

    try:
        with open(path, errors="ignore") as fh:
            for line in fh:
                if not line.strip():
                    continue
                seen += 1
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                parsed += 1
                p = d.get("payload", d)
                t = str(p.get("type", ""))

                # Codex records file writes as custom_tool_call(name=apply_patch) plus
                # patch_apply_end, NOT as a function_call: counting only function_call
                # misses every edit.
                if t == "patch_apply_end":
                    mutated += 1
                    continue

                if t in ("function_call", "custom_tool_call"):
                    tool_calls += 1
                    name = str(p.get("name", ""))
                    cmd = ""
                    args = p.get("arguments")
                    if isinstance(args, str):
                        try:
                            cmd = str(json.loads(args).get("cmd", ""))
                        except Exception:
                            cmd = args
                    elif isinstance(args, dict):
                        cmd = str(args.get("cmd", ""))
                    # Current rollouts carry the exec script in `input`; only the older
                    # orchestration tools still use `arguments`. Reading one shape only
                    # left cmd empty for every shell call, so nothing ever matched.
                    if isinstance(p.get("input"), str):
                        cmd = cmd + " " + p["input"]
                    probe = name + " " + cmd
                    is_write = name == "apply_patch" or bool(MUTATE.search(probe))
                    if is_write:
                        mutated += 1
                    # invocation only, never output
                    if CAPTURE.search(probe) or (is_write and KNOWLEDGE.search(probe)):
                        captured += 1

                # Explicit opt-out, stated by the assistant. A `message` payload also
                # carries developer- and user-role instruction injection, so the role is
                # checked: otherwise prompt text quoting the opt-out excuses every session.
                elif t in ("message", "assistant", "agent_message"):
                    if t == "message" and str(p.get("role", "")) != "assistant":
                        continue
                    blob = json.dumps(p)
                    if "no ingestible insight" in blob.lower():
                        declined = True
    except Exception:
        block(UNMEASURABLE)

    # A transcript whose every line is unparseable is unmeasurable, not an idle session.
    if seen and not parsed:
        block(UNMEASURABLE)

    substantive = mutated >= 1 or tool_calls >= envint("LEARN_TOOLUSE_READONLY", 20)

    if substantive and captured == 0 and not declined:
        block(BLOCKED)

    out(ALLOW)


if __name__ == "__main__":
    main()
