#!/usr/bin/env python3
"""Rank numbered knowledge entries by BM25.

Ranks ENTRIES rather than files, with IDF and length normalisation, so a hit is
already the citable unit the caller needs.

--verdict prefixes the output with `# coverage=<f> hits=<n>`: how much of the query,
weighted by IDF, the TOP hit contains. This script holds no threshold, the caller does.
--docs-json ranks documents from stdin instead of the file corpus and --pairs prints
them as key + body. rank() and tokenize() are corpus-agnostic either way.

Usage: bm25-search.py [-n N] [--json] [--files] [--verdict] <query terms...>
       bm25-search.py --docs-json --pairs [-n N] <query terms...> < docs.json
       bm25-search.py --skipped
"""

import json
import math
import os
import re
import sys

# Same resolution knowledge-search.sh uses, so both halves read one corpus, and a
# clone in the repo is not under $HOME.
HOME_DIR = os.environ.get("HARNESS_HOME") or os.path.expanduser("~/.agent-knowledge")
REFS_DIR = os.environ.get("HARNESS_REFS") or os.path.join(HOME_DIR, "references")
ORGS_DIR = os.environ.get("HARNESS_ORGS") or os.path.join(HOME_DIR, "orgs")
ENTRY_RE = re.compile(r"^(\d+)\. ")
# Matched on the ORIGINAL text: lowercasing first kills camel_parts()'s boundary.
TOKEN_RE = re.compile(r"[A-Za-z0-9]+(?:[-_][A-Za-z0-9]+)*")
CAMEL_RE = re.compile(r"[A-Z]+(?![a-z])|[A-Z][a-z0-9]*|[a-z0-9]+")
K1, B = 1.2, 0.75

# Closed-class words only: "set", "check", "run", "all", "no" and "re" are domain
# terms here, so they are deliberately absent.
STOPWORDS = frozenset("""
a an the this that these those
i we you he she it they them us me him her
my our your his its their
is are was were be been being am
do does did has have had
can could will would shall should may might must cannot
and or but if then than because while when where which who whom whose whether
though although
of in on at to for with from by as into onto about
not never only also very just even still already yet rather too
both each any some such
there here what how why so one
s t
""".split())


def camel_parts(word):
    """Sub-pieces of a camelCase/PascalCase word, or [] if it is not camel.

    A split with a one-character piece is rejected whole, not trimmed: mTLS splits as
    m + TLS, and emitting the long half broadens the query onto every TLS entry.
    """
    sub = CAMEL_RE.findall(word)
    return sub if len(sub) > 1 and all(len(s) > 1 for s in sub) else []


def tokenize(text):
    out = []
    for raw in TOKEN_RE.findall(text):
        pieces = [raw]
        parts = [p for p in re.split(r"[-_]", raw) if p] if ("-" in raw or "_" in raw) else [raw]
        if parts != [raw]:
            # Index identifiers whole AND by part, so either spelling finds them.
            pieces += parts
        for p in parts:
            pieces += camel_parts(p)
        out.extend(w for w in (x.lower() for x in pieces) if w not in STOPWORDS)
    return out


def doc_key(path):
    rel = os.path.relpath(path, HOME_DIR)
    return rel if rel.startswith("orgs/") else os.path.basename(path)


def corpus(skipped=None):
    """Every numbered entry, as (citation, text). One entry is one line.

    Files with no citable entries are collected into `skipped` when a list is
    passed, so the caller can fall back to a text match instead of dropping them.
    """
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
        # A repeated number means a procedural list, not entries: `#N` is ambiguous.
        if not seen or len(set(seen)) != len(seen):
            if skipped is not None:
                skipped.append(p)
            continue
        key = doc_key(p)
        for line, m in zip(lines, nums):
            if m:
                docs.append(("%s#%s" % (key, m.group(1)), line.rstrip("\n")))
    return docs


def json_docs(fh):
    """[(key, text)] from a `bd memories --json` payload on stdin.

    Tolerates both shapes bd emits, a {key: body} object and a list of {key, content}
    records, and returns None on a payload that will not parse, so an unreadable hive
    stays distinguishable from one that held no match.
    """
    try:
        d = json.load(fh)
    except Exception:
        return None
    items = d.items() if isinstance(d, dict) else [(m.get("key"), m.get("content", "")) for m in d]
    return [(k, " ".join(str(v).split())) for k, v in items if k]


class Ranked(list):
    """Hits, plus `coverage`: the share of the query the TOP hit actually answers.

    A list subclass, not a (hits, coverage) tuple: callers index and iterate it directly.
    """

    coverage = 0.0


def rank(query, docs, limit):
    q = [t for t in tokenize(query) if t]
    if not q or not docs:
        return Ranked()
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
            scored.append((s, docs[i][0], docs[i][1], i))
    scored.sort(key=lambda r: (-r[0], r[1]))
    top = scored[:limit]
    out = Ranked((s, cite, text) for s, cite, text, _ in top)
    if top:
        # Weighted by IDF: matching the two cheapest terms of five is not coverage.
        counts = tfs[top[0][3]]
        total = sum(idf[w] for w in set(q))
        if total:
            out.coverage = sum(idf[w] for w in set(q) if counts.get(w)) / total
    return out


def main():
    args = sys.argv[1:]
    limit, as_json, by_file, docs_json, pairs = 12, False, False, False, False
    list_skipped = verdict = False
    rest = []
    while args:
        a = args.pop(0)
        if a == "-n" and args:
            limit = int(args.pop(0))
        elif a == "--json":
            as_json = True
        elif a == "--files":
            by_file = True
        elif a == "--docs-json":
            docs_json = True
        elif a == "--pairs":
            pairs = True
        elif a == "--skipped":
            list_skipped = True
        elif a == "--verdict":
            verdict = True
        else:
            rest.append(a)
    if list_skipped:
        sk = []
        corpus(sk)
        print("\n".join(sk))
        return 0
    if not rest:
        print("\n".join(__doc__.strip().splitlines()[-3:]), file=sys.stderr)
        return 2
    bodies = {}
    if docs_json:
        docs = json_docs(sys.stdin)
        if docs is None:
            print("(bd memories unreadable)")
            return 0
        # A bd key is searchable, so index it with the body; display shows body alone.
        bodies = dict(docs)
        docs = [(k, k + " " + b) for k, b in docs]
    else:
        docs = corpus()
    hits = rank(" ".join(rest), docs, len(docs) if (by_file or pairs) else limit)
    matched = len(hits)
    if verdict:
        print("# coverage=%.3f hits=%d" % (hits.coverage, min(matched, limit)))
    if pairs:
        if not hits:
            print("(no matches in bd memories)")
            return 0
        for _s, key, text in hits[:limit]:
            text = bodies.get(key, text)
            print("  %s" % key)
            print("    %s" % (text[:320] + ("…" if len(text) > 320 else "")))
        if matched > limit:
            print()
            print("  ... %d more matches not shown, narrow the query or use: bd memories <keyword>"
                  % (matched - limit))
        return 0
    if by_file:
        hits = hits[:200]
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
        text = bodies.get(cite, text)
        # Strip the entry number by PATTERN: a --docs-json key carries no "#" to split.
        body = ENTRY_RE.sub("", text, count=1).strip() if text else ""
        print("%-42s %s" % (cite, body[:150]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
