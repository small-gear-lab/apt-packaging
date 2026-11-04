#!/bin/bash
# Build the storytold-photocraft debs (the PhotoCraft image editor and photocraft-cli, with its MCP server) from the upstream
# release tag, with the local rustup toolchain (not Ubuntu's rustc/cargo).
#
#   build.sh fetch [version]   download the tag tarball, check it, then `cargo vendor` every crate
#                              (needs the network; the only step that does)
#   build.sh build [version] [--no-clean]
#                              fresh unpack (or, with --no-clean, the work tree of the last build), check that the
#                              local rustc is new enough, build offline
#
# debian/ in this directory is the source of truth; the work tree is thrown away on every build.
# Layout: ~/.cache/photocraft-dl/{orig,deb/build,log}. The deb ends up in deb/build/. Add it with
#   sgl-reprepro includedeb resolute-testing ~/.cache/photocraft-dl/deb/build/storytold-photocraft*_<version>-*.deb
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# --no-clean (build only): keep the work tree of the last build (the unpacked source and target/), so that cargo
# only compiles what changed. Without it every build starts from a fresh tree.
noclean=0
args=()
for a in "$@"; do
    if [ "$a" = --no-clean ]; then noclean=1; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}
cmd=${1:-}
version=${2:-0.20.1}
dl=$HOME/.cache/photocraft-dl
orig=$dl/orig/photocraft-$version.tar.gz
vend=$dl/orig/photocraft-$version-vendor.tar.xz
bd=$dl/deb/build
work=$bd/storytold-photocraft-$version
repo=https://github.com/storytold/photocraft

# The local toolchain is rustup's. The build still runs in an empty environment (see curl-build.md for why),
# so this is the one place that names where cargo lives.
cargo_bin=$HOME/.cargo/bin
build_env() {
    env -i HOME="$HOME" LOGNAME="${LOGNAME:-$USER}" USER="${USER:-$LOGNAME}" LANG=C.UTF-8 TERM="${TERM:-dumb}" \
        PATH="$cargo_bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" \
        PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
        "$@"
}

# Upstream's [patch.crates-io] also names crates that nothing uses (Cargo.lock lists them as [[patch.unused]]).
# `cargo vendor` only keeps the crates that are used, so offline cargo cannot find the patch location of an unused one
# in vendor/ and stops. Drop those patches from Cargo.toml and from Cargo.lock together, so that --locked still holds.
drop_unused_patches() {
    python3 -I - <<'PY'
import re
from pathlib import Path
lock = Path("Cargo.lock")
toml = Path("Cargo.toml")
ltext = lock.read_text()
unused = re.findall(r'\[\[patch\.unused\]\]\nname = "([^"]+)"', ltext)
if not unused:
    print("no unused patches in Cargo.lock")
    raise SystemExit
ltext = re.sub(r'\n\[\[patch\.unused\]\]\nname = "[^"]+"\nversion = "[^"]+"\nsource = "[^"]+"\n', "\n", ltext)
ltext = ltext.rstrip("\n") + "\n"
if "patch.unused" in ltext:
    raise SystemExit("a [[patch.unused]] block has a shape this script does not know")
lock.write_text(ltext)
ttext = toml.read_text()
for name in unused:
    ttext, n = re.subn(r'(?m)^%s = \{ git = [^\n]*\}\n' % re.escape(name), "", ttext)
    if n != 1:
        raise SystemExit("expected exactly one [patch.crates-io] line for %s, found %d" % (name, n))
toml.write_text(ttext)
print("dropped unused patches: " + ", ".join(unused))
PY
}

# Highest `rust-version` among the packages the two programs really need (normal and build dependencies of
# photocraft and photocraft-cli, not dev/tools-only crates), compared with the installed rustc. Run inside an
# unpacked tree.
check_toolchain() {
    local meta required have
    meta=$(build_env cargo metadata --format-version 1 --locked --offline --filter-platform x86_64-unknown-linux-gnu)
    required=$(python3 -I -c '
import json, sys
m = json.loads(sys.stdin.read())
pk = {p["id"]: p for p in m["packages"]}
nodes = {n["id"]: n for n in m["resolve"]["nodes"]}
roots = [p["id"] for p in m["packages"] if p["name"] in ("photocraft", "photocraft-cli")]
seen, todo = set(), list(roots)
while todo:
    i = todo.pop()
    if i in seen:
        continue
    seen.add(i)
    for d in nodes[i]["deps"]:
        # dev-dependencies have kind "dev"; keep normal (None) and build kinds
        if any(k["kind"] in (None, "build") for k in d["dep_kinds"]):
            todo.append(d["pkg"])
def ver(s):
    return tuple(int(x) for x in s.split("."))
rows = sorted(((ver(pk[i]["rust_version"]), pk[i]["name"]) for i in seen if pk[i].get("rust_version")))
for v, n in rows[-3:]:
    print("%s\t%s" % (".".join(map(str, v)), n))
print("packages\t%d" % len(seen))
' <<<"$meta")
    have=$(build_env rustc --version | sed -E 's/^rustc ([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/')
    echo "toolchain: rustc $have ($(build_env rustup show active-toolchain 2>/dev/null | cut -d' ' -f1))"
    echo "strictest rust-version among $(sed -n 's/^packages\t//p' <<<"$required") crates:"
    sed -n '/^packages\t/!p' <<<"$required" | sed 's/^/  /'
    local need
    need=$(sed -n '/^packages\t/!p' <<<"$required" | tail -n 1 | cut -f1)
    if [ -n "$need" ] && [ "$(printf '%s\n%s\n' "$need" "$have" | sort -V | head -n 1)" != "$need" ]; then
        echo "rustc $have is older than the rust-version $need that the dependencies ask for" >&2
        exit 1
    fi
}

# The build environment is the builder's own business: nothing of it (Rust, a compiler) is a dependency of the
# installed package, and Build-Depends does not declare cargo or rustc. Say what is missing here instead of
# failing somewhere inside cargo.
check_prereqs() {
    local miss=()
    build_env sh -c 'command -v cargo >/dev/null && command -v rustc >/dev/null' \
        || miss+=("cargo and rustc (rustup: ~/.cargo/bin)")
    build_env sh -c 'command -v cc >/dev/null' || miss+=("a C compiler (cc)")
    build_env sh -c 'command -v pkg-config >/dev/null' || miss+=("pkg-config (pkgconf)")
    if [ ${#miss[@]} -gt 0 ]; then
        printf 'missing in the build environment:\n' >&2
        printf '  - %s\n' "${miss[@]}" >&2
        exit 1
    fi
}

case "$cmd" in
fetch)
    mkdir -p "$dl/orig"
    cd "$dl/orig"
    [ -f "$orig" ] || env -u LD_LIBRARY_PATH /usr/bin/curl -fsSL -o "$orig" "$repo/archive/refs/tags/v$version.tar.gz"
    # GitHub's tag tarballs are not signed. Tie it to the tag instead: the tarball records the commit it was
    # made from, which must equal the commit the tag points at on the remote.
    # (process substitution: git stops reading after one block, which would make gzip fail under pipefail)
    tar_commit=$(git get-tar-commit-id < <(gzip -dc "$orig"))
    tag_commit=$(git ls-remote "$repo" "refs/tags/v$version^{}" "refs/tags/v$version" | awk 'END{print $1}')
    [ -n "$tar_commit" ] && [ "$tar_commit" = "$tag_commit" ] \
        || { echo "tarball commit '$tar_commit' != tag commit '$tag_commit'" >&2; exit 1; }
    echo "tarball is the tag's commit $tar_commit"
    # Trust on first use for the bytes of the tarball: remember its sha256 next to this script.
    sum=$(sha256sum "$orig" | cut -d' ' -f1)
    if grep -q "  photocraft-$version.tar.gz\$" "$here/SHA256SUMS" 2>/dev/null; then
        [ "$(grep "  photocraft-$version.tar.gz\$" "$here/SHA256SUMS" | cut -d' ' -f1)" = "$sum" ] \
            || { echo "sha256 of $orig differs from SHA256SUMS" >&2; exit 1; }
        echo "sha256 matches SHA256SUMS"
    else
        echo "$sum  photocraft-$version.tar.gz" >> "$here/SHA256SUMS"
        echo "recorded sha256 $sum in SHA256SUMS (first use)"
    fi
    # Vendor every crate of Cargo.lock so that `build` needs no network. The result is a second tarball.
    # Git dependencies (the storytold family of egui and winit) are vendored too; cargo vendor writes the
    # source replacement for them into .cargo/config.toml.
    tmp=$(mktemp -d "$dl/vendor.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    tar -xzf "$orig" -C "$tmp"
    cd "$tmp/photocraft-$version"
    mkdir -p .cargo
    # --versioned-dirs: every directory gets its version (vendor/xml-0.8.10/). Without it a crate with a single
    # version is vendor/xml/, which the zbus-lockstep macros of atspi-common take for their `../xml` directory of
    # D-Bus XML files and panic on its LICENSE ("File has no extension").
    build_env cargo vendor --locked --versioned-dirs vendor > .cargo/config.toml
    tar -cJf "$vend" vendor .cargo
    echo "vendored $(find vendor -mindepth 1 -maxdepth 1 -type d | wc -l) crates into $vend ($(du -h "$vend" | cut -f1))"
    ;;
build)
    [ -f "$orig" ] && [ -f "$vend" ] || { echo "run '$0 fetch $version' first" >&2; exit 1; }
    mkdir -p "$bd"
    cp -f "$orig" "$bd/storytold-photocraft_$version.orig.tar.gz"
    if [ "$noclean" = 1 ] && [ -d "$work/vendor" ]; then
        echo "--no-clean: reusing the work tree $work"
    else
        rm -rf "$work" "$bd/photocraft-$version"
        # The tag tarball unpacks as photocraft-<version>; the work tree carries the source package's name.
        tar -xzf "$bd/storytold-photocraft_$version.orig.tar.gz" -C "$bd"
        mv "$bd/photocraft-$version" "$work"
        tar -xJf "$vend" -C "$work"
    fi
    # debian/ always comes from here, also in a kept tree.
    rsync -a --delete "$here/debian/" "$work/debian/"
    cd "$work"
    check_prereqs
    drop_unused_patches
    check_toolchain
    # The crates that are really linked in (normal dependencies of the two programs on this platform, with the
    # features the package builds), and their licenses: debian/copyright and debian/vendor-licenses/. It stops
    # the build for a crate whose license it cannot settle.
    {
        for p in photocraft photocraft-cli; do
            build_env CARGO_HOME="$work/debian/cargo-home" CARGO_NET_OFFLINE=true \
                cargo tree --locked --offline -p "$p" -F heif -e normal \
                --target x86_64-unknown-linux-gnu --prefix none --format '{p}|{l}'
        done
    } | sort -u > debian/linked-crates.txt
    python3 -I "$here/gen-crate-licenses.py" "$work" "$here/debian/copyright"
    # The binaries record the commit they were built from (the tarball knows it) and the date of this changelog entry.
    commit=$(git get-tar-commit-id < <(gzip -dc "$orig"))
    date=$(date -u -d "$(dpkg-parsechangelog -S Date)" +%Y-%m-%d)
    # -d: Build-Depends cannot see rustup's cargo/rustc, so dpkg's dependency check is skipped.
    # -nc: no `clean` first. dh_clean deletes *.orig, which includes the Cargo.toml.orig that every vendored crate
    # lists in its checksum file, and cargo then refuses the vendor directory. The tree is fresh anyway.
    build_env \
        CARGO_HOME="$work/debian/cargo-home" CARGO_NET_OFFLINE=true \
        PHOTOCRAFT_BUILD_SHA="$commit" PHOTOCRAFT_BUILD_DATE="$date" \
        DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
        dpkg-buildpackage -us -uc -b -d -nc
    echo "debs are in $bd"
    ;;
*)
    echo "usage: $0 fetch|build [version]" >&2
    exit 2
    ;;
esac
