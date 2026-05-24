#!/usr/bin/env python3
"""Compute context-window utilization from an agent session transcript.

Generic transcript parser, suitable for any agent runtime that emits JSONL
messages with a `content` array of `text` / `thinking` / `tool_use` /
`tool_result` blocks. Designed to back a statusline or a high-water-mark
PreCompact hook (see `core/hooks/factory-droid/ctx-threshold-warn.py`).

Reads `{"transcript_path": ..., "model": {"id": ...}, "session_id": ...}`
from stdin and prints a JSON result:
  {"pct": <0-100>, "tokens": <int>, "ctx_max": <int>, "model": <str>, "cpt": <float>}
"""
import json
import os
import sys

# Non-message overhead (system prompt, tool schemas, AGENTS.md, etc.). Calibrate
# for your runtime; ~19K is a good Claude-Code-class default.
SYSTEM_PROMPT_OVERHEAD = 19000

# Fallback when no compaction_state event is available for calibration.
CHARS_PER_TOKEN_DEFAULT = 4.0

CACHE_DIR = os.environ.get("AGENT_HARNESS_CACHE_DIR", "/tmp")

# Effective compaction limits (runtimes typically auto-compact before raw
# model context is hit). Extend for the models you actually run.
MODEL_CONTEXT_LIMITS = {
    "opus-4-6": 500000,
    "opus-4-7": 500000,
    "sonnet-4-6": 500000,
    "opus-4": 250000,
    "sonnet-4": 250000,
    "opus": 200000,
    "sonnet": 200000,
    "haiku": 200000,
    "claude": 200000,
    "gpt-5.4": 922000,
    "gpt-5": 500000,
    "gpt-4": 128000,
    "gemini": 1000000,
}


def get_context_limit(model_id: str) -> int:
    for key, limit in MODEL_CONTEXT_LIMITS.items():
        if key in model_id:
            return limit
    return 200000


def measure_message_chars(msg_content) -> int:
    """Char-count a single message's content array (text + thinking + tools)."""
    if isinstance(msg_content, str):
        return len(msg_content)
    if not isinstance(msg_content, list):
        return 0
    chars = 0
    for part in msg_content:
        if isinstance(part, str):
            chars += len(part)
            continue
        if not isinstance(part, dict):
            continue
        ptype = part.get("type", "")
        if ptype == "thinking":
            chars += len(part.get("thinking", "")) + len(part.get("text", ""))
        elif ptype == "text":
            chars += len(part.get("text", ""))
        elif ptype == "tool_use":
            inp = part.get("input", {})
            chars += len(json.dumps(inp)) if isinstance(inp, dict) else len(str(inp))
        elif ptype == "tool_result":
            rc = part.get("content", "")
            if isinstance(rc, str):
                chars += len(rc)
            elif isinstance(rc, list):
                for item in rc:
                    if isinstance(item, dict):
                        chars += len(item.get("text", ""))
                    elif isinstance(item, str):
                        chars += len(item)
            elif isinstance(rc, dict):
                chars += len(json.dumps(rc))
    return chars


def compute(transcript_path: str, model_id: str) -> dict:
    settings_path = transcript_path.replace(".jsonl", ".settings.json")
    real_model = model_id
    try:
        with open(settings_path) as f:
            real_model = json.load(f).get("model", model_id)
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    try:
        with open(transcript_path) as f:
            lines = f.readlines()
    except FileNotFoundError:
        return {"error": "transcript not found"}

    last_compact_line = -1
    last_summary_tokens = 0
    ratios: list[float] = []
    for i, line in enumerate(lines):
        try:
            o = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if o.get("type") == "compaction_state":
            last_compact_line = i
            last_summary_tokens = o.get("summaryTokens", 0) or 0
            st = o.get("summaryText", "") or ""
            stk = o.get("summaryTokens", 0) or 0
            if stk > 0 and len(st) > 0:
                ratios.append(len(st) / stk)

    if ratios:
        ratios.sort()
        chars_per_token = ratios[len(ratios) // 2]
    else:
        chars_per_token = CHARS_PER_TOKEN_DEFAULT

    all_chars = 0
    post_chars = 0
    for i, line in enumerate(lines):
        try:
            o = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if o.get("type") != "message":
            continue
        c = measure_message_chars(o.get("message", {}).get("content", []))
        all_chars += c
        if last_compact_line >= 0 and i > last_compact_line:
            post_chars += c

    ctx_max = get_context_limit(real_model)
    all_total = int(all_chars / chars_per_token) + SYSTEM_PROMPT_OVERHEAD
    post_total = int(post_chars / chars_per_token) + last_summary_tokens + SYSTEM_PROMPT_OVERHEAD

    if last_compact_line < 0 or all_total <= ctx_max:
        total_tokens = all_total
    else:
        total_tokens = post_total

    pct = min(total_tokens * 100 // ctx_max, 100)
    return {
        "pct": pct,
        "tokens": total_tokens,
        "ctx_max": ctx_max,
        "model": real_model,
        "cpt": round(chars_per_token, 2),
    }


def main() -> int:
    try:
        stdin_data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        print(json.dumps({"error": "no stdin"}))
        return 0

    transcript_path = stdin_data.get("transcript_path", "")
    model_id = stdin_data.get("model", {}).get("id", "")
    session_id = stdin_data.get("session_id", "")

    if not transcript_path:
        print(json.dumps({"error": "no transcript_path"}))
        return 0

    cache_file = os.path.join(CACHE_DIR, f"agent-ctx-{session_id}.json") if session_id else None
    cache_key = None
    try:
        st = os.stat(transcript_path)
        cache_key = f"{st.st_mtime_ns}:{st.st_size}"
    except OSError:
        pass

    if cache_file and cache_key and os.path.exists(cache_file):
        try:
            with open(cache_file) as f:
                cached = json.load(f)
            if cached.get("_key") == cache_key:
                cached.pop("_key", None)
                print(json.dumps(cached))
                return 0
        except (json.JSONDecodeError, OSError):
            pass

    result = compute(transcript_path, model_id)
    if cache_file and cache_key and "error" not in result:
        try:
            with open(cache_file, "w") as f:
                json.dump({**result, "_key": cache_key}, f)
        except OSError:
            pass

    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
