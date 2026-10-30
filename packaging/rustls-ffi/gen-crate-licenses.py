#!/usr/bin/python3 -I
"""Account for the Rust crates that are linked into librustls.

Usage: gen-crate-licenses.py <work tree> <base copyright>

The work tree is the rustls-ffi source with `cargo vendor` already unpacked into vendor/. build.sh has put the crates
that are really linked in (the normal dependencies of rustls-ffi for this platform, with the features the package is
built with; `cargo tree --prefix none --format '{p}|{l}'`) into debian/linked-crates.txt, one per line.

For each of them this copies the license files the crate ships (also those in sub-directories, as aws-lc-sys has
them) into debian/vendor-licenses/<crate>-<version>/, which debian/librustls*.docs installs, and appends a paragraph to
debian/copyright, which is written as <base copyright> plus the generated paragraphs and the license paragraphs
they need. The license of a crate is what its Cargo.toml declares (an SPDX expression); the holders come from its
license files, or from `authors` when it ships none.

An expression is `group AND group ...`, a group being one license or a choice `(a OR b OR c)`. Every group applies;
inside a choice the options whose license text is available (shipped by a crate, in the base copyright, or on every
Debian system) are the ones listed, since we are free to pick. It stops the build for a crate it cannot account for
(not in vendor/, a group none of whose options has a text, `WITH` exceptions), so that a new upstream version cannot
slip a license past unseen.
"""
import re
import shutil
import sys
import tomllib
from pathlib import Path

work = Path(sys.argv[1])
base_copyright = Path(sys.argv[2])
vendor = work / "vendor"
out_docs = work / "debian" / "vendor-licenses"
out_copyright = work / "debian" / "copyright"
listing = work / "debian" / "linked-crates.txt"

LICENSE_FILE = re.compile(r"^(licen[cs]e|copying|notice|unlicense)([._-].*)?$", re.I)
SKIP_DIRS = {"tests", "test", "benches", "examples", "target", ".git", "fuzz"}
MAX_DEPTH = 4
# Licenses whose full text is on every Debian system.
COMMON = {"Apache-2.0": "Apache-2.0", "CC0-1.0": "CC0-1.0", "MPL-2.0": "MPL-2.0"}
DEBIAN_NAME = {"MIT": "Expat"}  # the SPDX name -> the name Debian's copyright format uses
NOTICE = re.compile(r"^\s*(?:copyright\s*(?:\(c\)|©)\s*|copyright\s+(?=\d)|\(c\)\s+(?=\d)|©\s*)(.+?)\s*$", re.I)


def classify(text):
    """The licenses whose text is in the file, as Debian short names; [] when none is recognised."""
    t = re.sub(r"\s+", " ", text.lower())
    found = []
    if "apache license" in t and "version 2.0" in t:
        found.append("Apache-2.0")
    if "mozilla public license" in t and ("version 2.0" in t or "v. 2.0" in t):
        found.append("MPL-2.0")
    if "cc0 1.0 universal" in t or ("creative commons legal code" in t and "cc0" in t):
        found.append("CC0-1.0")
    if "permission to use, copy, modify, and/or distribute this software for any purpose with or without fee" in t:
        found.append("ISC")
    if "altered source versions must be plainly marked as such" in t:
        found.append("Zlib")
    if "redistribution and use in source and binary forms" in t:
        if "advertising materials" in t:
            return []
        if "neither the name" in t or "the names of its contributors" in t:
            found.append("BSD-3-Clause")
        elif "redistributions in binary form must reproduce" in t:
            found.append("BSD-2-Clause")
    if "permission is hereby granted, free of charge, to any person obtaining a copy" in t:
        # MIT-0 is the MIT text without the condition that the notice be kept
        found.append("Expat" if "the above copyright notice and this permission notice shall be included" in t else "MIT-0")
    return found


def holders(text):
    found = []
    for line in text.splitlines():
        m = NOTICE.match(line)
        if not m:
            continue
        h = m.group(1)
        if "[yyyy]" in h or "owner" in h.lower():
            continue
        h = re.sub(r"\s*All rights reserved\.?$", "", h, flags=re.I).strip(" .")
        if h and h not in found:
            found.append(h)
    return found[:6]


def license_files(d):
    out = []
    stack = [(d, 0)]
    while stack:
        cur, depth = stack.pop()
        for p in sorted(cur.iterdir()):
            if p.is_dir() and not p.is_symlink() and depth < MAX_DEPTH and p.name not in SKIP_DIRS:
                stack.append((p, depth + 1))
            elif p.is_file() and LICENSE_FILE.match(p.name):
                out.append(p)
    return sorted(out)


def split_top(expr, sep):
    """Split at `sep` where it is not inside parentheses."""
    parts, buf, depth, i = [], "", 0, 0
    while i < len(expr):
        c = expr[i]
        depth += (c == "(") - (c == ")")
        if depth == 0 and expr.startswith(sep, i):
            parts.append(buf)
            buf, i = "", i + len(sep)
            continue
        buf += c
        i += 1
    parts.append(buf)
    return parts


def parse_groups(expr):
    """`a AND (b OR c) AND d` -> [[a], [b, c], [d]] with Debian short names; None for `WITH`."""
    if re.search(r"\sWITH\s", expr):
        return None
    expr = re.sub(r"(?<=\w)/(?=\w)", " OR ", expr)        # old style `A/B` means a choice
    groups = []
    for g in split_top(expr.strip(), " AND "):
        g = g.strip()
        while g.startswith("(") and g.endswith(")") and len(split_top(g[1:-1], " OR ")) >= 1 and g.count("(") == 1:
            g = g[1:-1].strip()
        alts = [DEBIAN_NAME.get(a.strip(" ()"), a.strip(" ()")) for a in split_top(g, " OR ")]
        groups.append([a for a in alts if a])
    return groups


def flowed(text):
    lines = [l.rstrip() for l in text.strip("\n").splitlines()]
    return "\n".join(" " + l if l else " ." for l in lines)


# --- what is linked, and where it lives in vendor/
linked = {}
for line in listing.read_text().splitlines():
    line = re.sub(r"\s+\(\*\)\s*$", "", line.strip())
    if not line or "|" not in line:
        continue
    left, lic = line.split("|", 1)
    m = re.match(r"^(\S+) v(\S+)(?: \((.*)\))?$", left.strip())
    if not m or (m.group(3) or "").startswith("/"):   # the root package carries a local path
        continue
    linked[(m.group(1), m.group(2))] = (lic.strip(), (m.group(3) or ""))

index = {}
for d in vendor.iterdir():
    t = d / "Cargo.toml"
    if t.is_file():
        pkg = tomllib.loads(t.read_text())["package"]
        index[(pkg["name"], pkg["version"])] = (d, pkg)

base = base_copyright.read_text()
defined = set(re.findall(r"(?m)^License: (\S+)\n ", base))   # paragraphs that carry a license text

# --- pass 1: copy every crate's license files, learn the license texts that are available
shutil.rmtree(out_docs, ignore_errors=True)
texts, crates, problems = {}, [], []
for (name, version), (expr, kind) in sorted(linked.items()):
    if (name, version) not in index:
        problems.append((name, "not in vendor/ (run `build.sh fetch` again?)"))
        continue
    d, pkg = index[(name, version)]
    files = license_files(d)
    held = []
    for f in files:
        text = f.read_text(errors="replace")
        for h in holders(text):
            if h not in held:
                held.append(h)
        ids = classify(text)
        if len(ids) == 1:  # the text of a license is taken from a file that holds only that license
            texts.setdefault(ids[0], "\n".join(l for l in text.splitlines() if not re.match(r"^\s*copyright\b", l, re.I)))
        dest = out_docs / ("%s-%s" % (name, version)) / f.relative_to(d)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(f, dest)  # not copy2: a crate's files may carry the date 1970-01-01, which lintian rejects
    crates.append((d, pkg, pkg.get("license") or expr, kind, files, held or list(pkg.get("authors", [])) or ["see Cargo.toml of the crate"]))

available = set(texts) | defined | set(COMMON)

# --- pass 2: settle the license of each crate
entries, used = [], set()
for d, pkg, expr, kind, files, held in crates:
    groups = parse_groups(expr)
    if not groups:
        problems.append((pkg["name"], "license expression not handled: %r" % expr))
        continue
    chosen = []
    for alts in groups:
        ok = [a for a in alts if a in available]
        if not ok:
            problems.append((pkg["name"], "none of %s has a license text available" % " / ".join(alts)))
            break
        chosen.append(ok)
    else:
        used |= {a for ok in chosen for a in ok}
        text = ", and ".join(" or ".join(ok) for ok in chosen) if any(len(ok) > 1 for ok in chosen) and len(chosen) > 1 \
            else (" and ".join(" or ".join(ok) for ok in chosen))
        note = ""
        if not files:
            note = "The crate ships no license file; its Cargo.toml declares %s, and the holder is taken from its authors." % expr
        elif len(groups) > 1 or any(len(g) > 1 for g in groups):
            note = "Cargo.toml declares: %s" % expr
            if any(set(ok) != set(g) for ok, g in zip(chosen, groups)):
                note += ". Of a choice, the options whose text is at hand are listed."
        entries.append((d.name, pkg["name"], pkg["version"], text, held, bool(files), note, kind))

if problems:
    print("crates whose license could not be settled:", file=sys.stderr)
    for what, why in problems:
        print("  %s: %s" % (what, why), file=sys.stderr)
    sys.exit(1)

parts = [base.rstrip("\n"), ""]
for dirname, name, version, lic, held, has_files, note, kind in entries:
    parts.append("Files: vendor/%s/*" % dirname)
    parts.append("Copyright: %s" % "\n ".join(held))
    parts.append("License: %s" % lic)
    comment = "Rust crate %s %s%s, linked statically into librustls." % (
        name, version, " (a proc-macro, used at build time)" if "proc-macro" in kind else "")
    if has_files:
        comment += " Its license file(s) as the crate ships them: /usr/share/doc/librustls*/vendor-licenses/%s-%s/" % (name, version)
    if note:
        comment += " " + note
    parts.append("Comment: " + "\n ".join(re.findall(r".{1,100}(?:\s|$)", comment)).rstrip())
    parts.append("")

for lic in sorted(used - defined):
    parts.append("License: %s" % lic)
    if lic in COMMON:
        parts.append(" On Debian systems, the full text of the license can be found in")
        parts.append(" /usr/share/common-licenses/%s." % COMMON[lic])
    else:
        parts.append(flowed(texts[lic]))
    parts.append("")

out_copyright.write_text("\n".join(parts).rstrip("\n") + "\n")

width = max(len(e[1]) + len(e[2]) + 1 for e in entries)
for dirname, name, version, lic, held, has_files, note, kind in entries:
    print("  %-*s  %-52s %s" % (width, name + " " + version, lic[:52], ("(no license file) " if not has_files else "") + "; ".join(held)[:36]))
print("%d crates; new license paragraphs: %s" % (len(entries), ", ".join(sorted(used - defined)) or "none"))
