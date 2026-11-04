#!/bin/bash
# Build the storytold-craft-fonts metapackage (it only depends on other packages; nothing is fetched).
#
#   build.sh build   fresh work tree, build the deb
#
# Layout: ~/.cache/storytold-craft-fonts-dl/deb/build. Add the deb with
#   sgl-reprepro includedeb resolute ~/.cache/storytold-craft-fonts-dl/deb/build/storytold-craft-fonts_*.deb
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
version=1
bd=$HOME/.cache/storytold-craft-fonts-dl/deb/build
work=$bd/storytold-craft-fonts-$version
case "${1:-}" in
build)
    mkdir -p "$bd"
    rm -rf "$work"
    mkdir -p "$work"
    rsync -a "$here/debian/" "$work/debian/"
    cd "$work"
    env -i HOME="$HOME" LOGNAME="${LOGNAME:-$USER}" USER="${USER:-$LOGNAME}" LANG=C.UTF-8 TERM="${TERM:-dumb}" \
        PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        dpkg-buildpackage -us -uc -b -nc
    echo "debs are in $bd"
    ;;
*)
    echo "usage: $0 build" >&2
    exit 2
    ;;
esac
