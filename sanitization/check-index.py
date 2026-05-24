#!/usr/bin/env python3
"""Verify every backtick or markdown-linked path in references/index.md exists."""
import re
import sys
from pathlib import Path


PATH_PATTERN = re.compile(r"`([^`]+)`|\]\(([^)]+)\)")


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    index = root / "references/index.md"
    if not index.exists():
        print("references/index.md not found")
        return 1

    missing: list[str] = []
    for line in index.read_text().splitlines():
        if not line.startswith("|"):
            continue
        for match in PATH_PATTERN.finditer(line):
            token = match.group(1) or match.group(2)
            if not token:
                continue
            if any(ch in token for ch in (" ", "<", ">", "$", "*")):
                continue
            if token.startswith(("http", "git ", "bd ", "graphify ", "rtk ", "gcx ", "yq ", "jq ", "kubectl ", "helm ", "brew ", "pipx ", "curl ", "/", "~/")):
                continue
            # Only validate things that look like file paths.
            if "/" not in token and not token.endswith(
                (".md", ".sh", ".py", ".yaml", ".yml", ".json", ".toml", ".txt")
            ):
                continue
            # Resolve relative to the index file's directory.
            target = (index.parent / token).resolve()
            if not target.exists() and not (root / token).exists():
                missing.append(token)

    if missing:
        print("Missing index paths:")
        for path in missing:
            print(f"  {path}")
        return 1
    print("index ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
