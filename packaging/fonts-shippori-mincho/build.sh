#!/bin/bash
# Build the fonts-shippori-mincho deb from the font files of google/fonts at a pinned commit.
#
#   build.sh fetch   download the files, check each against its git blob hash (below), remember the sha256
#   build.sh build   fresh work tree, build the deb (no compiler involved: the files are installed as they are)
#
# Layout: ~/.cache/fonts-shippori-mincho-dl/{orig,deb/build}. Add the deb with
#   sgl-reprepro includedeb resolute-testing ~/.cache/fonts-shippori-mincho-dl/deb/build/fonts-shippori-mincho_*.deb
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cmd=${1:-}
commit=9710da1eacb3be272583c3224dcb70f9da6eadbb
version=0~git20260930.9710da1
dl=$HOME/.cache/fonts-shippori-mincho-dl
src=$dl/orig/upstream
bd=$dl/deb/build
work=$bd/fonts-shippori-mincho-$version
base=https://raw.githubusercontent.com/google/fonts/$commit/ofl/shipporimincho

# file -> git blob hash at that commit (from the GitHub contents API of google/fonts)
declare -A blob=(
    [DESCRIPTION.en_us.html]=a2439f21a0dfda4c8396e4b4ca48f413a8f63225
    [OFL.txt]=a3f24cb5d7e61907ac03eecd760cb1e65a9eaef4
    [ShipporiMincho-Bold.ttf]=f56e74f4c468b6594ecf6446e83c960f6add1a9e
    [ShipporiMincho-ExtraBold.ttf]=06e44efe0da2e5e9296081009508f3bb00ff951f
    [ShipporiMincho-Medium.ttf]=b0afeb289e438fff78c9c98fc56079f3f15f8700
    [ShipporiMincho-Regular.ttf]=cfc25ceb7fd744599d6bde767cb2a01e73b510a4
    [ShipporiMincho-SemiBold.ttf]=17078edde2eefaaa6d230583d16ff8df3ecaacf0
    [upstream_info.md]=51cc68035f1d7f50339f5e03fc79270d007204c9
)

case "$cmd" in
fetch)
    mkdir -p "$src"
    for f in "${!blob[@]}"; do
        [ -f "$src/$f" ] || env -u LD_LIBRARY_PATH /usr/bin/curl -fsSL -o "$src/$f" "$base/$f"
        # `git hash-object` is the blob id that GitHub lists for the file at that commit, so it ties the bytes to it.
        got=$(git hash-object "$src/$f")
        [ "$got" = "${blob[$f]}" ] || { echo "$f: blob $got != ${blob[$f]}" >&2; exit 1; }
    done
    echo "all ${#blob[@]} files match their git blob hashes at $commit"
    (cd "$src" && sha256sum -- * ) > "$here/SHA256SUMS.new"
    if [ -f "$here/SHA256SUMS" ]; then
        diff -u "$here/SHA256SUMS" "$here/SHA256SUMS.new" && rm "$here/SHA256SUMS.new"
        echo "sha256 matches SHA256SUMS"
    else
        mv "$here/SHA256SUMS.new" "$here/SHA256SUMS"
        echo "recorded sha256 in SHA256SUMS (first use)"
    fi
    ;;
build)
    [ -f "$src/ShipporiMincho-Regular.ttf" ] || { echo "run '$0 fetch' first" >&2; exit 1; }
    mkdir -p "$bd"
    rm -rf "$work"
    mkdir -p "$work"
    tar -C "$dl/orig" -czf "$bd/fonts-shippori-mincho_$version.orig.tar.gz" upstream
    cp -a "$src" "$work/upstream"
    rsync -a "$here/debian/" "$work/debian/"
    cd "$work"
    env -i HOME="$HOME" LOGNAME="${LOGNAME:-$USER}" USER="${USER:-$LOGNAME}" LANG=C.UTF-8 TERM="${TERM:-dumb}" \
        PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        dpkg-buildpackage -us -uc -b -nc
    echo "debs are in $bd"
    ;;
*)
    echo "usage: $0 fetch|build" >&2
    exit 2
    ;;
esac
