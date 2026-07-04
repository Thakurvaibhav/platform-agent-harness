#!/usr/bin/env python3
"""
UserPromptSubmit hook: trajectory-aware compaction nudge.

Improvements over a flat-percentage threshold:
  * Trajectory, not a flat %: samples token usage once per turn, computes
    delta-tokens/turn, and projects turns-to-ceiling. On a 1M window a flat "85%"
    is a useless tripwire; "~3 turns to compaction" is actionable.
  * Two-tier + debounced: a one-time soft note (~5 turns out), then a hard
    nudge + bd checkpoint (~2 turns out). No per-prompt nagging.
  * Resets after a compaction (token count drops), so it re-arms naturally.
  * Limit is auto-derived from the statusline's per-session cache (which sees the
    true model id). No hardcoded env required.

Configuration (env vars):
  CTX_COMPACT_DISABLE   "1" disables the hook silently
  CTX_SOFT_PCT          soft-warn percentage (default 65)
  CTX_SOFT_TURNS        soft-warn turns-to-ceiling threshold (default 5)
  CTX_HARD_PCT          hard-warn percentage (default 85)
  CTX_HARD_TURNS        hard-warn turns-to-ceiling threshold (default 2)
  CTX_MAX_TOKENS        last-resort limit if statusline cache unavailable
  CTX_STATUSLINE_PATH   override for statusline-context.py location
  CTX_PRECOMPACT_HOOK   override for pre-compact-bd-sync.py location
"""
import importlib.util
import json
import os
import subprocess
import sys

TMP = "/tmp"
MAX_SAMPLES = 12

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


def _envint(name, default):
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


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


def statusline_ctx_max(session_id):
    """ctx_max as recorded by the statusline (which sees the real model id)."""
    if not session_id:
        return None
    try:
        with open(os.path.join(TMP, f"claude-ctx-{session_id}.json")) as f:
            v = int(json.load(f).get("ctx_max", 0) or 0)
            return v or None
    except (OSError, json.JSONDecodeError, ValueError):
        return None


def load_hist(session_id):
    try:
        with open(os.path.join(TMP, f"claude-ctx-hist-{session_id}.json")) as f:
            d = json.load(f)
            return d.get("samples", []), int(d.get("warned_tier", 0)), int(d.get("peak", 0))
    except (OSError, json.JSONDecodeError, ValueError):
        return [], 0, 0


def save_hist(session_id, samples, warned_tier, peak):
    try:
        with open(os.path.join(TMP, f"claude-ctx-hist-{session_id}.json"), "w") as f:
            json.dump({"samples": samples, "warned_tier": warned_tier, "peak": peak}, f)
    except OSError:
        pass


def main():
    if os.environ.get("CTX_COMPACT_DISABLE") == "1":
        sys.exit(0)

    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    transcript_path = data.get("transcript_path", "")
    if not transcript_path or not os.path.isfile(transcript_path):
        sys.exit(0)

    compute = load_compute()
    if compute is None:
        sys.exit(0)

    model_id = data.get("model", {}).get("id", "") if isinstance(data.get("model"), dict) else ""
    try:
        result = compute(transcript_path, model_id)
    except Exception:
        sys.exit(0)
    if "error" in result:
        sys.exit(0)

    tokens = int(result.get("tokens", 0))
    session_id = data.get("session_id", "")
    ctx_max = statusline_ctx_max(session_id) or int(result.get("ctx_max", 0)) \
        or _envint("CTX_MAX_TOKENS", 200000)
    if ctx_max <= 0:
        sys.exit(0)

    samples, warned_tier, peak = load_hist(session_id)

    # Detect a compaction (big drop vs peak) -> re-arm.
    if peak and tokens < 0.6 * peak:
        samples, warned_tier = [], 0
    peak = max(peak, tokens)

    # Sample once per turn (only when the number moves).
    if not samples or samples[-1] != tokens:
        samples.append(tokens)
        samples = samples[-MAX_SAMPLES:]

    # Velocity = mean positive delta over the last few turns.
    deltas = [b - a for a, b in zip(samples, samples[1:])]
    recent = [d for d in deltas[-5:] if d > 0]
    vel = (sum(recent) / len(recent)) if recent else 0

    pct = tokens * 100 // ctx_max
    headroom = ctx_max - tokens
    turns_left = (headroom / vel) if vel > 0 else float("inf")

    soft_pct, soft_turns = _envint("CTX_SOFT_PCT", 65), _envint("CTX_SOFT_TURNS", 5)
    hard_pct, hard_turns = _envint("CTX_HARD_PCT", 85), _envint("CTX_HARD_TURNS", 2)

    hit_hard = pct >= hard_pct or turns_left <= hard_turns
    hit_soft = pct >= soft_pct or turns_left <= soft_turns

    tl = "stable" if turns_left == float("inf") else f"~{int(turns_left)} turn(s)"
    vel_h = f"+{int(vel):,}/turn" if vel > 0 else "flat"

    msg = None
    if hit_hard and warned_tier < 2:
        status = "bd checkpoint attempted"
        if os.path.isfile(PRE_COMPACT_HOOK):
            try:
                r = subprocess.run(["python3", PRE_COMPACT_HOOK], input=json.dumps(data),
                                   text=True, capture_output=True, timeout=20)
                if r.returncode != 0:
                    status = "bd checkpoint hook returned non-zero"
            except Exception:
                status = "bd checkpoint hook failed"
        msg = (f"[context-budget] {pct}% used ({tokens:,}/{ctx_max:,}), growth {vel_h}, "
               f"{tl} to ceiling. {status}. Run `/compact` now at this clean boundary "
               "rather than mid-tool-chain. If bd context looks stale after restore, "
               "rerun `bd prime` from the repo root.")
        warned_tier = 2
    elif hit_soft and warned_tier < 1:
        msg = (f"[context-budget] {pct}% used ({tokens:,}/{ctx_max:,}), growth {vel_h}, "
               f"{tl} to ceiling. Heads-up: consider `/compact` at the next natural "
               "stopping point before long tool chains.")
        warned_tier = 1

    save_hist(session_id, samples, warned_tier, peak)

    if msg:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit", "additionalContext": msg}}))
    sys.exit(0)


if __name__ == "__main__":
    main()
