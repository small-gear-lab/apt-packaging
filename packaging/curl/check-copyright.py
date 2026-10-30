#!/usr/bin/python3 -I
"""Check debian/copyright against the source tree it describes.

Usage: check-copyright.py <unpacked upstream tree> <debian/copyright>

What it finds, with the license each file states about itself (SPDX-License-Identifier) as the reference:
  1. files whose own SPDX tag disagrees with the paragraph that covers them,
  2. Files paragraphs that match no file of this tree (stale: the file was removed or renamed upstream),
  3. files that carry no SPDX tag and are covered only by the catch-all `Files: *`,
  4. the copyright years of the catch-all paragraph against the year in the tree's COPYING.
DEP-5 matching rules: `*` and `?` also match `/`, and the last paragraph that matches a file wins.
Exit status 0 when nothing needs attention, 1 otherwise.
"""
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

tree = Path(sys.argv[1])
copyright_file = Path(sys.argv[2])

# re.M: in `#`-comment headers the tag runs to the end of its line, with no closing token.
SPDX = re.compile(r"SPDX-License-Identifier:[ \t]*([^\n*]+?)[ \t]*(?:\*/|-->|$)", re.M)
SKIP_DIRS = {".git", "autom4te.cache"}


def glob_regex(pattern):
    out = []
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if c == "\\" and i + 1 < len(pattern):
            out.append(re.escape(pattern[i + 1]))
            i += 2
            continue
        out.append(".*" if c == "*" else "." if c == "?" else re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")


def parse_paragraphs(text):
    paras = []
    for block in re.split(r"\n\s*\n", text):
        lines = [l for l in block.splitlines() if not l.startswith("#")]
        if not lines:
            continue
        fields, key = {}, None
        for line in lines:
            if line[:1] in " \t" and key:
                fields[key] += "\n" + line.strip()
            elif ":" in line:
                key, _, val = line.partition(":")
                fields[key] = val.strip()
        paras.append(fields)
    return paras


def tokens(expr):
    """The license names in a Debian License line or an SPDX expression, lower-cased."""
    return {t.strip().lower() for t in re.split(r"\s+(?:and|or)\s+|[()]", expr.split("\n")[0], flags=re.I) if t.strip()}


paras = [p for p in parse_paragraphs(copyright_file.read_text()) if "Files" in p]
rules = []  # (regex list, paragraph)
for p in paras:
    pats = [glob_regex(x) for x in p["Files"].split()]
    rules.append((pats, p))

files = sorted(p.relative_to(tree).as_posix() for p in tree.rglob("*")
               if p.is_file() and not (set(p.relative_to(tree).parts) & SKIP_DIRS) and not p.is_symlink())


def covering(path):
    hit = None
    for pats, p in rules:
        if any(r.match(path) for r in pats):
            hit = p
    return hit


matches_any = [False] * len(rules)
mismatch = defaultdict(list)
untagged = defaultdict(list)
for path in files:
    for i, (pats, _p) in enumerate(rules):
        if any(r.match(path) for r in pats):
            matches_any[i] = True
    para = covering(path)
    try:
        head = (tree / path).read_text(errors="strict")[:3000]
    except (UnicodeDecodeError, OSError):
        continue  # binary
    m = SPDX.search(head)
    if m:
        want = tokens(m.group(1))
        have = tokens(para["License"]) if para else set()
        if not want <= have:
            mismatch[(m.group(1).strip(), para["License"].split("\n")[0] if para else "(not covered)")].append(path)
    elif para is not None and para["Files"].strip() == "*":
        untagged[path.split("/")[0] if "/" in path else "(top level)"].append(path)

problems = 0

print("== 1. files whose SPDX tag disagrees with the covering paragraph")
if not mismatch:
    print("   none")
for (want, have), paths in sorted(mismatch.items(), key=lambda kv: -len(kv[1])):
    problems += 1
    print("   tag '%s' but paragraph says '%s': %d file(s), e.g. %s" % (want, have, len(paths), ", ".join(paths[:3])))

print("== 2. Files paragraphs that match nothing in this tree")
stale = [rules[i][1]["Files"].split("\n")[0] for i in range(len(rules))
         if not matches_any[i] and not rules[i][1]["Files"].strip().startswith("debian/")]
if not stale:
    print("   none")
for s in stale:
    problems += 1
    print("   " + s)

print("== 3. files without an SPDX tag that only the catch-all `Files: *` covers (top-level directory: count)")
if not untagged:
    print("   none")
for d, paths in sorted(untagged.items(), key=lambda kv: -len(kv[1])):
    print("   %-14s %5d   e.g. %s" % (d, len(paths), ", ".join(paths[:2])))

print("== 4. copyright years")
star = next((p for p in paras if p["Files"].strip() == "*"), None)
copying = (tree / "COPYING").read_text() if (tree / "COPYING").exists() else ""
m = re.search(r"Copyright \(c\) (\d{4}) - (\d{4})", copying)
claimed = re.search(r"(\d{4})-(\d{4})", star["Copyright"]) if star else None
if m and claimed:
    ok = m.group(2) == claimed.group(2)
    print("   COPYING says %s-%s, `Files: *` says %s-%s%s" % (m.group(1), m.group(2), claimed.group(1), claimed.group(2),
                                                           "" if ok else "   <-- out of date"))
    problems += 0 if ok else 1
else:
    print("   could not compare")

sys.exit(1 if problems else 0)
