#!/bin/bash
# Build the rustls-ffi debs (the C bindings of Rustls that curl's --with-rustls needs) from the upstream
# release tag, with the local rustup toolchain (not Ubuntu's rustc/cargo).
#
#   build.sh fetch [version]   download the tag tarball, check it, then `cargo vendor` every crate
#                              (needs the network; the only step that does)
#   build.sh build [version]   fresh unpack, check that the local rustc is new enough, build offline
#
# debian/ in this directory is the source of truth; the work tree is thrown away on every build.
# Layout: ~/.cache/rustls-ffi-dl/{orig,deb/build,log}. The debs end up in deb/build/. Add them with
#   sgl-reprepro includedeb resolute ~/.cache/rustls-ffi-dl/deb/build/*_<version>-*.deb
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cmd=${1:-}
version=${2:-0.15.7}
dl=$HOME/.cache/rustls-ffi-dl
orig=$dl/orig/rustls-ffi-$version.tar.gz
vend=$dl/orig/rustls-ffi-$version-vendor.tar.xz
bd=$dl/deb/build
work=$bd/rustls-ffi-$version
repo=https://github.com/rustls/rustls-ffi

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

# Highest `rust-version` among the packages the library really needs (normal and build dependencies of
# rustls-ffi, not dev/tools-only crates), compared with the installed rustc. Run inside an unpacked tree.
check_toolchain() {
    local meta required have
    meta=$(build_env cargo metadata --format-version 1 --locked --offline --filter-platform x86_64-unknown-linux-gnu)
    # the python reads the metadata from stdin and prints "<minimum>\t<crate that needs it>" lines, strictest last
    required=$(python3 -I -c '
import json, sys
m = json.loads(sys.stdin.read())
pk = {p["id"]: p for p in m["packages"]}
nodes = {n["id"]: n for n in m["resolve"]["nodes"]}
root = next(p["id"] for p in m["packages"] if p["name"] == "rustls-ffi")
seen, todo = set(), [root]
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

# The build environment is the builder's own business: nothing of it (Rust, cargo-c, cmake, a compiler)
# is a dependency of the installed packages, and Build-Depends does not declare it. Say what is missing
# here instead of failing somewhere inside cargo.
check_prereqs() {
    local miss=()
    build_env sh -c 'command -v cargo >/dev/null && command -v rustc >/dev/null' \
        || miss+=("cargo and rustc (rustup: ~/.cargo/bin)")
    build_env sh -c 'command -v cargo-cinstall >/dev/null' || miss+=("cargo-c (cargo install cargo-c --locked)")
    build_env sh -c 'command -v cmake >/dev/null' || miss+=("cmake")
    build_env sh -c 'command -v cc >/dev/null' || miss+=("a C compiler (cc)")
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
    if grep -q "  rustls-ffi-$version.tar.gz\$" "$here/SHA256SUMS" 2>/dev/null; then
        [ "$(grep "  rustls-ffi-$version.tar.gz\$" "$here/SHA256SUMS" | cut -d' ' -f1)" = "$sum" ] \
            || { echo "sha256 of $orig differs from SHA256SUMS" >&2; exit 1; }
        echo "sha256 matches SHA256SUMS"
    else
        echo "$sum  rustls-ffi-$version.tar.gz" >> "$here/SHA256SUMS"
        echo "recorded sha256 $sum in SHA256SUMS (first use)"
    fi
    # Vendor every crate of Cargo.lock so that `build` needs no network. The result is a second tarball.
    tmp=$(mktemp -d "$dl/vendor.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    tar -xzf "$orig" -C "$tmp"
    cd "$tmp/rustls-ffi-$version"
    mkdir -p .cargo
    build_env cargo vendor --locked vendor > .cargo/config.toml
    tar -cJf "$vend" vendor .cargo
    echo "vendored $(find vendor -mindepth 1 -maxdepth 1 -type d | wc -l) crates into $vend ($(du -h "$vend" | cut -f1))"
    ;;
build)
    [ -f "$orig" ] && [ -f "$vend" ] || { echo "run '$0 fetch $version' first" >&2; exit 1; }
    mkdir -p "$bd"
    cp -f "$orig" "$bd/rustls-ffi_$version.orig.tar.gz"
    rm -rf "$work"
    tar -xzf "$bd/rustls-ffi_$version.orig.tar.gz" -C "$bd"
    tar -xJf "$vend" -C "$work"
    rsync -a "$here/debian/" "$work/debian/"
    cd "$work"
    check_prereqs
    check_toolchain
    # The library package is named after the soname, which carries the whole upstream version (librustls.so.<version>).
    for f in debian/*@SOVER@*; do mv "$f" "${f//@SOVER@/$version}"; done
    sed -i "s/@SOVER@/$version/g" debian/control debian/rules
    # The crates that are really linked in (normal dependencies of rustls-ffi on this platform, with the features the
    # package builds), and their licenses: debian/copyright and debian/vendor-licenses/. It stops the build for a crate
    # whose license it cannot settle.
    build_env CARGO_HOME="$work/debian/cargo-home" CARGO_NET_OFFLINE=true \
        cargo tree --locked --offline -p rustls-ffi -e normal --features cert_compression \
        --target x86_64-unknown-linux-gnu --prefix none --format '{p}|{l}' | sort -u > debian/linked-crates.txt
    python3 -I "$here/gen-crate-licenses.py" "$work" "$here/debian/copyright"
    # -d: Build-Depends cannot see rustup's cargo/rustc, so dpkg's dependency check is skipped. The cargo
    # that cargo-c calls comes from PATH (rustup), and CARGO_NET_OFFLINE keeps it away from the network.
    # -nc: no `clean` first. dh_clean deletes *.orig, which includes the Cargo.toml.orig that every vendored crate
    # lists in its checksum file, and cargo then refuses the vendor directory. The tree is fresh anyway.
    build_env \
        CARGO_HOME="$work/debian/cargo-home" CARGO_NET_OFFLINE=true \
        DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
        dpkg-buildpackage -us -uc -b -d -nc
    echo "debs are in $bd"
    ;;
*)
    echo "usage: $0 fetch|build [version]" >&2
    exit 2
    ;;
esac
