#!/usr/bin/python3 -I
"""Account for the licenses of the Go code that is linked into kitty's Go programs (kitten).

Usage: gen-vendor-licenses.py <work tree> <base copyright> [<overrides> [<extra holders>]]

The work tree is kitty's source with `go mod vendor` already run. For every module in vendor/modules.txt
this copies the module's license files, as the module ships them, into debian/vendor-licenses/<module>/
(debian/kitty.docs installs that directory) and appends a paragraph for it to debian/copyright, which is
written as <base copyright> plus the generated paragraphs. The Go standard library and runtime, which are
linked in too, get the same treatment from GOROOT.

The license of a module is told from the text of its license file. A module whose license is not
recognised, or that carries no license file, stops the build: look at it, then name its license in the
overrides file, one `module<TAB>license` per line, using the Debian short name (Expat is MIT).
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

work = Path(sys.argv[1])
base_copyright = Path(sys.argv[2])
overrides_file = Path(sys.argv[3]) if len(sys.argv) > 3 else None
extra_file = Path(sys.argv[4]) if len(sys.argv) > 4 else None

vendor = work / "vendor"
out_docs = work / "debian" / "vendor-licenses"
out_copyright = work / "debian" / "copyright"

LICENSE_FILE = re.compile(r"^(licen[cs]e|copying|notice|patents|unlicense)([._-].*)?$", re.I)
MAIN_FILE = re.compile(r"^(licen[cs]e|copying|unlicense)([._-].*)?$", re.I)

# Licenses whose full text is on every Debian system (a paragraph can point to it instead of repeating it).
COMMON = {"Apache-2.0": "Apache-2.0", "MPL-2.0": "MPL-2.0"}


def classify(text):
    """Every license whose text is in the file, as Debian short names. One file may hold several (a module
    that also carries BSD code under its Apache license, say); an empty list means nothing was recognised
    or a license that is not handled here (BSD with the advertising clause)."""
    t = re.sub(r"\s+", " ", text.lower())
    found = []
    if "apache license" in t and "version 2.0" in t:
        found.append("Apache-2.0")
    if "mozilla public license" in t and ("version 2.0" in t or "v. 2.0" in t):
        found.append("MPL-2.0")
    if "free and unencumbered software released into the public domain" in t:
        found.append("Unlicense")
    if "permission to use, copy, modify, and/or distribute this software for any purpose with or without fee" in t:
        found.append("ISC")
    if "redistribution and use in source and binary forms" in t:
        if "advertising materials" in t:
            return []
        if "neither the name" in t or "the names of its contributors" in t:
            found.append("BSD-3-Clause")
        elif "redistributions in binary form must reproduce" in t:
            found.append("BSD-2-Clause")
    if "permission is hereby granted, free of charge, to any person obtaining a copy" in t:
        found.append("Expat")
    return found


# A copyright notice: "Copyright (c) ...", "Copyright (C) ...", "Copyright © ...", "Copyright 2013 ...", "(c) ..."
# or "© ...". A line that merely starts with the word (a wrapped sentence of the license text) is not one.
NOTICE = re.compile(r"^\s*(?:copyright\s*(?:\(c\)|©)\s*|copyright\s+(?=\d)|\(c\)\s+(?=\d)|©\s*)(.+?)\s*$", re.I)


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
    return sorted(p for p in d.iterdir() if p.is_file() and LICENSE_FILE.match(p.name))


def find_license_dir(module):
    """The module's own directory, or the nearest parent inside vendor/ (monorepos put it at the root)."""
    d = vendor / module
    while True:
        if d.is_dir() and license_files(d):
            return d
        if d == vendor or d.parent == d:
            return None
        d = d.parent


def modules():
    mods = []
    cur = None
    for line in (vendor / "modules.txt").read_text().splitlines():
        if line.startswith("# "):
            cur = line.split()[1]
        elif line.startswith("## "):
            continue
        elif line.strip() and cur is not None:
            if cur not in mods:
                mods.append(cur)
    return mods


def goroot():
    r = subprocess.run(["go", "env", "GOROOT"], capture_output=True, text=True,
                       env={"PATH": "/usr/bin:/bin", "GOTOOLCHAIN": "local"})
    p = Path(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else Path("/usr/lib/go")
    return p


def flowed(text):
    """License text as DEP-5 continuation lines."""
    lines = [l.rstrip() for l in text.strip("\n").splitlines()]
    return "\n".join(" " + l if l else " ." for l in lines)


overrides = {}
if overrides_file and overrides_file.exists():
    for line in overrides_file.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            m, lic = line.split("\t")[:2]
            overrides[m] = lic

# Copyright holders that the source files name but the license file does not: `module<TAB>holder` per line.
extra_holders = {}
if extra_file and extra_file.exists():
    for line in extra_file.read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            m, holder = line.split("\t")[:2]
            extra_holders.setdefault(m, []).append(holder)

base = base_copyright.read_text()
defined = set(re.findall(r"(?m)^License: (\S+)\n ", base))  # paragraphs that carry a license text

shutil.rmtree(out_docs, ignore_errors=True)
entries = []   # (name, license, holders, doc subdir)
texts = {}     # license -> text of one example, for paragraphs the base does not have
problems = []

for module in modules():
    d = find_license_dir(module)
    if d is None:
        problems.append((module, "no license file in the module or any parent inside vendor/"))
        continue
    files = license_files(d)
    main = next((f for f in files if MAIN_FILE.match(f.name)), files[0])
    text = main.read_text(errors="replace")
    ids = overrides[module].split(" and ") if module in overrides else classify(text)
    if not ids:
        problems.append((module, "license not recognised: %s" % main.relative_to(vendor)))
        continue
    dest = out_docs / module
    dest.mkdir(parents=True)
    for f in files:
        shutil.copy(f, dest / f.name)  # not copy2: a module's files may carry the date 1970-01-01, which lintian rejects
    if len(ids) == 1:  # the text of a license is taken from a file that holds only that license
        texts.setdefault(ids[0], "\n".join(l for l in text.splitlines() if not re.match(r"^\s*copyright\b", l, re.I)))
    entries.append((module, " and ".join(ids), holders(text) + [h for h in extra_holders.get(module, []) if h not in holders(text)], module))

def go_license():
    """(text, license name) of the Go toolchain that builds kitty: GOROOT/LICENSE when it has one, else the
    'License: Go' paragraph (BSD-3-Clause plus Google's patent grant) in the copyright file of Debian's
    golang-<version>-go package. Raises LookupError when neither exists."""
    go = goroot()
    if (go / "LICENSE").exists():
        text = (go / "LICENSE").read_text()
        if (go / "PATENTS").exists():
            text += "\n" + (go / "PATENTS").read_text()
        return text, " and ".join(classify(text) or ["BSD-3-Clause"])
    copyright_file = Path("/usr/share/doc") / ("golang-%s-go" % go.name.replace("go-", "", 1)) / "copyright"
    if copyright_file.exists():
        for para in copyright_file.read_text().split("\n\n"):
            lines = para.strip("\n").splitlines()
            if lines and lines[0] == "License: Go":
                body = [(l[1:] if l.startswith(" ") else l) for l in lines[1:]]
                return "\n".join("" if l == "." else l for l in body), "Go"
    raise LookupError("no LICENSE in %s and no 'License: Go' paragraph in %s" % (go, copyright_file))


# The Go standard library and runtime.
try:
    text, lic = go_license()
except LookupError as e:
    problems.append(("go-standard-library", str(e)))
else:
    dest = out_docs / "go-standard-library"
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "LICENSE").write_text(text.rstrip("\n") + "\n")
    texts.setdefault(lic, "\n".join(l for l in text.splitlines() if not re.match(r"^\s*copyright\b", l, re.I)))
    entries.append(("go-standard-library", lic, holders(text), "go-standard-library"))

needed = {i for e in entries for i in e[1].split(" and ")}
for lic in sorted(needed - defined - set(COMMON) - set(texts)):
    problems.append((lic, "its text is not in the base copyright and no module holds it alone: add the paragraph there"))

if problems:
    print("vendored code whose license could not be settled:", file=sys.stderr)
    for module, why in problems:
        print("  %s: %s" % (module, why), file=sys.stderr)
    print("Look at it, then add 'module<TAB>license' to the overrides file.", file=sys.stderr)
    sys.exit(1)

parts = [base.rstrip("\n"), ""]
for module, lic, hs, sub in entries:
    parts.append("Files: %s" % ("debian/vendor-licenses/go-standard-library/*" if module == "go-standard-library"
                                  else "vendor/%s/*" % module))
    parts.append("Copyright: %s" % ("\n ".join(hs) if hs else "see the license file in /usr/share/doc/kitty/vendor-licenses/%s/" % sub))
    parts.append("License: %s" % lic)
    parts.append("Comment: %s linked statically into kitty's Go programs. The license file(s) as the module\n"
                 " ships them: /usr/share/doc/kitty/vendor-licenses/%s/"
                 % ("The Go standard library and runtime are" if module == "go-standard-library" else "Go module %s is" % module, sub))
    parts.append("")

# Paragraphs for licenses that the base copyright does not spell out.
for lic in sorted(needed - defined):
    parts.append("License: %s" % lic)
    if lic in COMMON:
        parts.append(" On Debian systems, the full text of the license can be found in")
        parts.append(" /usr/share/common-licenses/%s." % COMMON[lic])
    else:
        parts.append(flowed(texts[lic]))
    parts.append("")

out_copyright.write_text("\n".join(parts).rstrip("\n") + "\n")

width = max(len(e[0]) for e in entries)
for module, lic, hs, sub in entries:
    print("  %-*s  %-12s %s" % (width, module, lic, "; ".join(hs)[:60] or "(no copyright line)"))
print("%d modules + the Go standard library; new license paragraphs: %s"
      % (len(entries) - 1, ", ".join(sorted(needed - defined)) or "none"))
