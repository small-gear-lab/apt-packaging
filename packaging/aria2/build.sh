#!/bin/bash
# Rebuild the aria2 debs (Ubuntu's 1.37.0+debian-4 plus the SOCKS5 patch) from this directory's debian/.
#
#   build.sh fetch [version]   download Ubuntu's source package of aria2 (orig tarball) into ~/.cache/aria2-dl/orig/
#                              (apt-get source, so it is verified through the archive's signed metadata)
#   build.sh build [version] [--no-clean]
#                              unpack the orig tarball afresh (or, with --no-clean, keep the work tree of the last
#                              build), copy debian/ into it and build the debs
#
# debian/ in this directory is the source of truth (Ubuntu's debian/ + debian/patches/socks5-proxy.patch);
# the work tree is thrown away on every build.
# The debs end up in ~/.cache/aria2-dl/deb/build/. Add them with:
#   sgl-reprepro includedeb resolute ~/.cache/aria2-dl/deb/build/*_<version>-*.deb
set -euo pipefail
# -h/--help: the comment at the top of this file, before anything else is read or done.
for a in "$@"; do
    case "$a" in -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done

here=$(cd "$(dirname "$0")" && pwd)
noclean=0
args=()
for a in "$@"; do
    if [ "$a" = --no-clean ]; then noclean=1; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}
nc=()
[ "$noclean" = 1 ] && nc=(-nc)
cmd=${1:-}
version=${2:-1.37.0}
dl=$HOME/.cache/aria2-dl
orig=$dl/orig/aria2_$version.orig.tar.gz
bd=$dl/deb/build
work=$bd/aria2-$version

case "$cmd" in
fetch)
    mkdir -p "$dl/orig"
    # apt-get source reads deb-src from /etc/apt/sources.list.d/ubuntu.sources. Only the orig tarball is kept.
    tmp=$(mktemp -d "$dl/fetch.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    (cd "$tmp" && apt-get source --download-only aria2)
    cp "$tmp"/aria2_"$version"+debian.orig.tar.gz "$orig" 2>/dev/null \
        || cp "$tmp"/aria2_*.orig.tar.gz "$orig"
    echo "orig: $orig"
    ;;
build)
    [ -f "$orig" ] || { echo "run '$0 fetch $version' first" >&2; exit 1; }
    mkdir -p "$bd"
    if [ "$noclean" = 0 ]; then
        rm -rf "$work"
        mkdir -p "$work"
        tar -xzf "$orig" -C "$work" --strip-components=1
        # dpkg-source wants the orig tarball next to the work tree, named after the upstream version of the changelog
        cp "$orig" "$bd/aria2_$version+debian.orig.tar.gz"
    fi
    rsync -a --delete "$here/debian/" "$work/debian/"
    cd "$work"
    # Start from an empty environment, like a real builder (no LD_RUN_PATH / PKG_CONFIG_PATH / /usr/local leaking in).
    env -i \
        HOME="$HOME" LOGNAME="${LOGNAME:-$USER}" USER="${USER:-$LOGNAME}" LANG=C.UTF-8 TERM="${TERM:-dumb}" \
        PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
        DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
        dpkg-buildpackage -us -uc -b ${nc[@]+"${nc[@]}"}
    echo "debs are in $bd"
    ;;
*)
    echo "usage: $0 fetch|build [version] [--no-clean]" >&2
    exit 2
    ;;
esac
