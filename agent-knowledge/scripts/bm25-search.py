#!/usr/bin/env python3
"""Rank numbered knowledge entries by BM25.

The ripgrep path ranks FILES by raw match count, which has no length
normalisation and no IDF: the two 370 KB files win queries they have nothing to
do with, and a generic term weighs the same as a rare one. This ranks ENTRIES,
so the result is already the citable unit the caller needs.

Usage: bm25-search.py [-n N] [--json] [--files] <query terms...>
"""

import json
import math
import os
import re
import sys

# Same resolution knowledge-search.sh uses, so both halves of the search read one
# corpus. A clone lives in the repo, not under $HOME, and hardcoding the latter
# would make every adopter search an empty tree.
HOME_DIR = os.environ.get("HARNESS_HOME") or os.path.expanduser("~/.agent-knowledge")
REFS_DIR = os.environ.get("HARNESS_REFS") or os.path.join(HOME_DIR, "references")
ORGS_DIR = os.environ.get("HARNESS_ORGS") or os.path.join(HOME_DIR, "orgs")
ENTRY_RE = re.compile(r"^(\d+)\. ")
# Keep hyphenated and underscored identifiers whole (kube-dns, force_ssl) AND
# index their parts, so a query for either spelling finds the entry.
TOKEN_RE = re.compile(r"[a-z0-9]+(?:[-_][a-z0-9]+)*")
K1, B = 1.2, 0.75


def tokenize(text):
    out = []
    for t in TOKEN_RE.findall(text.lower()):
        out.append(t)
        if "-" in t or "_" in t:
            out.extend(p for p in re.split(r"[-_]", t) if p)
    return out


def doc_key(path):
    rel = os.path.relpath(path, HOME_DIR)
    return rel if rel.startswith("orgs/") else os.path.basename(path)


def corpus():
    """Every numbered entry, as (citation, text). One entry is one line."""
    paths = []
    refs = REFS_DIR
    if os.path.isdir(refs):
        paths += [os.path.join(refs, f) for f in sorted(os.listdir(refs))
                  if f.startswith("learnings-") and f.endswith(".md")]
    orgs = ORGS_DIR
    if os.path.isdir(orgs):
        for org in sorted(os.listdir(orgs)):
            d = os.path.join(orgs, org)
            if os.path.isdir(d):
                paths += [os.path.join(d, f) for f in sorted(os.listdir(d))
                          if f.endswith(".md")]
    docs = []
    for p in paths:
        try:
            with open(p, encoding="utf-8") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        nums = [ENTRY_RE.match(l) for l in lines]
        seen = [int(m.group(1)) for m in nums if m]
        # A repeated number means the file is a procedural list, not entries:
        # `#N` would be ambiguous, so it is not citable and is skipped.
        if not seen or len(set(seen)) != len(seen):
            continue
        key = doc_key(p)
        for line, m in zip(lines, nums):
            if m:
                docs.append(("%s#%s" % (key, m.group(1)), line.rstrip("\n")))
    return docs


def rank(query, docs, limit):
    q = [t for t in tokenize(query) if t]
    if not q or not docs:
        return []
    toks = [tokenize(text) for _, text in docs]
    lens = [len(t) for t in toks]
    avg = sum(lens) / float(len(lens))
    tfs = []
    df = {}
    for t in toks:
        counts = {}
        for w in t:
            counts[w] = counts.get(w, 0) + 1
        tfs.append(counts)
        for w in counts:
            df[w] = df.get(w, 0) + 1
    n = len(docs)
    idf = {}
    for w in set(q):
        d = df.get(w, 0)
        idf[w] = math.log(1 + (n - d + 0.5) / (d + 0.5))
    scored = []
    for i, counts in enumerate(tfs):
        s = 0.0
        for w in q:
            f = counts.get(w, 0)
            if not f:
                continue
            s += idf[w] * (f * (K1 + 1)) / (f + K1 * (1 - B + B * lens[i] / avg))
        if s > 0:
            scored.append((s, docs[i][0], docs[i][1]))
    scored.sort(key=lambda r: (-r[0], r[1]))
    return scored[:limit]


def main():
    args = sys.argv[1:]
    limit, as_json, by_file = 12, False, False
    rest = []
    while args:
        a = args.pop(0)
        if a == "-n" and args:
            limit = int(args.pop(0))
        elif a == "--json":
            as_json = True
        elif a == "--files":
            by_file = True
        else:
            rest.append(a)
    if not rest:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    hits = rank(" ".join(rest), corpus(), 200 if by_file else limit)
    if by_file:
        best = {}
        for s, cite, _ in hits:
            f = cite.split("#", 1)[0]
            if s > best.get(f, 0):
                best[f] = s
        hits = [(s, f, "") for f, s in sorted(best.items(), key=lambda kv: -kv[1])][:limit]
    if as_json:
        print(json.dumps([{"score": round(s, 3), "cite": c, "text": t} for s, c, t in hits]))
        return 0
    if not hits:
        print("(no matches)")
        return 0
    for s, cite, text in hits:
        body = text[len(cite.split("#")[1]) + 2:].strip() if text else ""
        print("%-42s %s" % (cite, body[:150]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
