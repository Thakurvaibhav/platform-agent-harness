#!/usr/bin/env python3
"""Formatting check: trailing whitespace + missing trailing newline."""
import sys
from pathlib import Path


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    issues: list[str] = []
    for p in root.rglob("*"):
        if p.is_dir() or ".git" in p.parts or "__pycache__" in p.parts:
            continue
        data = p.read_bytes()
        if data and not data.endswith(b"\n"):
            issues.append(f"{p.relative_to(root)}: missing trailing newline")
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            if line.rstrip() != line:
                issues.append(f"{p.relative_to(root)}:{i}: trailing whitespace")
    if issues:
        print("\n".join(issues))
        return 1
    print("format ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
