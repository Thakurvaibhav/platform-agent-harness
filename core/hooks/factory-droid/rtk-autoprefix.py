#!/usr/bin/env python3
"""
PreToolUse hook (matcher: Execute).

Automatically prefix shell commands with `rtk` when the command matches the
allowlist below. Saves tokens on verbose read-only output without making the
agent remember to type `rtk` every time.

Skips when:
  - the command already starts with `rtk`
  - the command contains shell chaining / substitution (| && || ; $() `` <( >()
  - the command is not on the allowlist
  - `rtk` is not installed
"""
import json
import re
import shutil
import sys

# (prefix-tuple, description). Longest match wins.
ALLOWLIST = [
    # Git read ops
    (("git", "status"), "git status"),
    (("git", "diff"), "git diff"),
    (("git", "log"), "git log"),
    (("git", "show"), "git show"),
    (("git", "branch"), "git branch"),
    # GitHub CLI read ops
    (("gh", "pr", "list"), "gh pr list"),
    (("gh", "pr", "view"), "gh pr view"),
    (("gh", "pr", "diff"), "gh pr diff"),
    (("gh", "issue", "list"), "gh issue list"),
    (("gh", "issue", "view"), "gh issue view"),
    (("gh", "run", "view"), "gh run view"),
    (("gh", "run", "list"), "gh run list"),
    # Containers / k8s read-only
    (("docker", "ps"), "docker ps"),
    (("docker", "logs"), "docker logs"),
    (("kubectl", "get"), "kubectl get"),
    (("kubectl", "describe"), "kubectl describe"),
    (("kubectl", "logs"), "kubectl logs"),
    (("kubectl", "top"), "kubectl top"),
    # Helm read / check
    (("helm", "template"), "helm template"),
    (("helm", "lint"), "helm lint"),
    (("helm", "dependency", "build"), "helm dependency build"),
    (("helm", "show", "values"), "helm show values"),
    # Build / test / check
    (("cargo", "test"), "cargo test"),
    (("cargo", "build"), "cargo build"),
    (("npm", "test"), "npm test"),
    (("pnpm", "test"), "pnpm test"),
    (("pytest",), "pytest"),
    (("go", "test"), "go test"),
    (("go", "build"), "go build"),
    (("tsc",), "tsc"),
    # Infra planning
    (("terraform", "plan"), "terraform plan"),
    # Observability reads
    (("gcx", "--agent"), "gcx --agent"),
]

SKIP_PREFIXES = {"sudo", "time", "nice", "ionice", "env", "command"}


def split_prefix_and_argv(command: str) -> tuple[list[str], list[str]]:
    tokens = command.strip().split()
    prefix: list[str] = []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tok):
            prefix.append(tok)
            i += 1
            continue
        if tok in SKIP_PREFIXES:
            prefix.append(tok)
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                prefix.append(tokens[i])
                i += 1
            continue
        break
    return prefix, tokens[i:]


def has_shell_chaining(command: str) -> bool:
    for marker in ("|", "&&", "||", ";", "$(", "`", "<(", ">("):
        if marker in command:
            return True
    return False


def match_allowlist(argv: list[str]) -> bool:
    for prefix, _ in ALLOWLIST:
        if len(argv) >= len(prefix) and tuple(argv[: len(prefix)]) == prefix:
            return True
    return False


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    if data.get("tool_name") != "Execute":
        return 0

    tool_input = data.get("tool_input") or {}
    command = tool_input.get("command", "")
    if not isinstance(command, str) or not command.strip():
        return 0

    stripped = command.lstrip()
    if stripped.startswith("rtk ") or stripped == "rtk":
        return 0

    if has_shell_chaining(command):
        return 0

    if shutil.which("rtk") is None:
        return 0

    prefix_tokens, argv = split_prefix_and_argv(command)
    if not argv or not match_allowlist(argv):
        return 0

    new_command = " ".join(prefix_tokens + ["rtk"] + argv)

    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "permissionDecisionReason": f"rtk-autoprefix: {argv[0]}{(' ' + argv[1]) if len(argv) > 1 else ''}",
            "updatedInput": {"command": new_command},
        },
        "suppressOutput": True,
    }
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
