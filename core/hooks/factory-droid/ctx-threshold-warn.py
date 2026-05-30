#!/usr/bin/env python3
"""
UserPromptSubmit hook: warn before context fills.

Uses `core/statusline/statusline-context.py` to compute actual transcript
utilization (matching the statusline). When utilization crosses a configurable
threshold, injects an `additionalContext` block reminding the agent to run
`/compact` (or the runtime's equivalent) at a quiet moment rather than mid-turn.

When the threshold is crossed, the hook also actively runs the PreCompact hook
(pre-compact-bd-sync.py) as a deliberate checkpoint, so bd memories are
snapshotted at that moment rather than only when compaction eventually fires.

Configuration (env vars):
  CTX_COMPACT_THRESHOLD   percentage 0-100, default 85
  CTX_COMPACT_DISABLE     "1" disables the hook silently
  CTX_STATUSLINE_PATH     override for statusline-context.py location
  CTX_PRECOMPACT_HOOK     override for pre-compact-bd-sync.py location
"""
import importlib.util
import json
import os
import subprocess
import sys

DEFAULT_THRESHOLD = 85

# Sibling PreCompact hook, resolved relative to this file. Override with
# CTX_PRECOMPACT_HOOK. No organisation-specific path is hard-coded.
PRE_COMPACT_HOOK = os.environ.get(
    "CTX_PRECOMPACT_HOOK",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "pre-compact-bd-sync.py"),
)

DEFAULT_STATUSLINE_PATHS = [
    os.environ.get("CTX_STATUSLINE_PATH", ""),
    os.path.expanduser("~/.agents/statusline/statusline-context.py"),
    os.path.expanduser("~/.factory/statusline-context.py"),
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "..", "..", "statusline", "statusline-context.py",
    ),
]


def load_compute():
    for path in DEFAULT_STATUSLINE_PATHS:
        if not path:
            continue
        path = os.path.abspath(path)
        if not os.path.isfile(path):
            continue
        spec = importlib.util.spec_from_file_location("_ctx_statusline", path)
        if spec is None or spec.loader is None:
            continue
        try:
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        except Exception:
            continue
        compute = getattr(module, "compute", None)
        if compute is not None:
            return compute
    return None


def main() -> int:
    if os.environ.get("CTX_COMPACT_DISABLE") == "1":
        return 0

    try:
        threshold = int(os.environ.get("CTX_COMPACT_THRESHOLD", DEFAULT_THRESHOLD))
    except ValueError:
        threshold = DEFAULT_THRESHOLD

    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    transcript_path = data.get("transcript_path", "")
    if not transcript_path or not os.path.isfile(transcript_path):
        return 0

    compute = load_compute()
    if compute is None:
        return 0

    try:
        result = compute(transcript_path, "")
    except Exception:
        return 0

    if "error" in result:
        return 0

    pct = int(result.get("pct", 0))
    tokens = int(result.get("tokens", 0))
    ctx_max = int(result.get("ctx_max", 250000))

    if pct < threshold:
        return 0

    checkpoint_status = (
        "A pre-compaction bd checkpoint was attempted now so memories are current."
    )
    if os.path.isfile(PRE_COMPACT_HOOK):
        try:
            result = subprocess.run(
                ["python3", PRE_COMPACT_HOOK],
                input=json.dumps(data),
                text=True,
                capture_output=True,
                timeout=20,
            )
            if result.returncode != 0:
                checkpoint_status = (
                    "A pre-compaction bd checkpoint was attempted but the hook "
                    "returned non-zero."
                )
        except Exception:
            checkpoint_status = (
                "A pre-compaction bd checkpoint was attempted but the hook failed "
                "to execute."
            )
    else:
        checkpoint_status = (
            "No PreCompact hook found to checkpoint bd memories automatically."
        )

    msg = (
        f"[context-budget] Context window is at {pct}% "
        f"({tokens:,}/{ctx_max:,} tokens), above the {threshold}% threshold. "
        f"{checkpoint_status} Consider running `/compact` (or the runtime equivalent) "
        "before continuing long tool chains. The PreCompact hook will also run again "
        "on manual or auto compaction; if bd context looks stale after restore, retry "
        "`bd prime` from the repo root and add a manual `bd remember` checkpoint."
    )

    out = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": msg,
        }
    }
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
