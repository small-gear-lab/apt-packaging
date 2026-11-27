#!/usr/bin/env python3
"""Write a license-only copy of every crate's source into vendor/, for gen-crate-licenses.py.

effectcraft's Cargo.lock pulls the same craft-libs crate (name and version) from several git revisions, which
`cargo vendor` refuses ("found duplicate version of package"). So build.sh does not vendor: it snapshots a CARGO_HOME
that `cargo fetch --locked` filled, and builds offline from that. gen-crate-licenses.py still wants a vendor/<crate>-<version>/
tree to read license files from; this makes one with Cargo.toml, the license-like files that script looks for, and the
two source files it reads (src/fdct.rs, fonts/UFL.txt). Where two sources carry the same name and version, the first wins.

usage: snapshot-licenses.py <cargo metadata json> <crate-cache dir> <out vendor dir>
"""
import json
import re
import shutil
import sys
import tarfile
from pathlib import Path

meta = json.loads(Path(sys.argv[1]).read_text())
cache = Path(sys.argv[2])          # registry/cache/<index>/
out = Path(sys.argv[3])
LICENSE_FILE = re.compile(r"^(licen[cs]e|copying|notice|unlicense)([._-].*)?$", re.I)
SKIP_DIRS = {"tests", "test", "benches", "examples", "target", ".git", "fuzz"}
MAX_DEPTH = 4
EXTRA = {"src/fdct.rs", "fonts/UFL.txt"}

out.mkdir(parents=True, exist_ok=True)
done, n = set(), 0
for p in sorted(meta["packages"], key=lambda p: (p["name"], p["version"], p["id"])):
    key = (p["name"], p["version"])
    if key in done or p["source"] is None:
        continue
    done.add(key)
    dest = out / ("%s-%s" % key)
    manifest = Path(p["manifest_path"])
    if p["source"].startswith("registry+"):
        crate = next(cache.glob("%s-%s.crate" % key), None)
        if crate is None:
            sys.exit("no %s in %s" % (crate, cache))
        with tarfile.open(crate) as tf:
            for m in tf.getmembers():
                rel = Path(*Path(m.name).parts[1:])
                if not m.isfile() or not rel.parts:
                    continue
                name = rel.name
                keep = (str(rel) == "Cargo.toml" or str(rel) in EXTRA or
                        (LICENSE_FILE.match(name) and len(rel.parts) <= MAX_DEPTH + 1
                         and not (set(rel.parts[:-1]) & SKIP_DIRS)))
                if keep:
                    (dest / rel).parent.mkdir(parents=True, exist_ok=True)
                    (dest / rel).write_bytes(tf.extractfile(m).read())
    else:
        base = manifest.parent
        stack = [(base, 0)]
        while stack:
            cur, depth = stack.pop()
            for q in sorted(cur.iterdir()):
                rel = q.relative_to(base)
                if q.is_dir() and not q.is_symlink() and depth < MAX_DEPTH and q.name not in SKIP_DIRS:
                    stack.append((q, depth + 1))
                elif q.is_file() and (str(rel) == "Cargo.toml" or str(rel) in EXTRA or LICENSE_FILE.match(q.name)):
                    (dest / rel).parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy(q, dest / rel)
        # A git crate's own Cargo.toml may inherit its fields from the workspace (version.workspace = true), which
        # gen-crate-licenses.py cannot read. Write the resolved values that cargo metadata reports instead.
        lines = ["[package]", "name = %s" % json.dumps(p["name"]), "version = %s" % json.dumps(p["version"])]
        if p.get("license"):
            lines.append("license = %s" % json.dumps(p["license"]))
        if p.get("authors"):
            lines.append("authors = [%s]" % ", ".join(json.dumps(a) for a in p["authors"]))
        (dest / "Cargo.toml").write_text("\n".join(lines) + "\n")
    if not (dest / "Cargo.toml").is_file():
        sys.exit("no Cargo.toml captured for %s %s" % key)
    n += 1
print("license tree for %d crates in %s" % (n, out))
