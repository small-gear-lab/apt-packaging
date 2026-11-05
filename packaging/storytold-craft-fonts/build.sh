#!/bin/bash
# Build the storytold-craft-fonts metapackage (it only depends on other packages; nothing is fetched).
#
#   build.sh build [--no-clean]
#                    fresh work tree, build the deb. --no-clean is accepted for the same interface as the other
#                    build.sh and changes nothing
#
# Layout: ~/.cache/storytold-craft-fonts-dl/deb/build. Add the deb with
#   sgl-reprepro includedeb resolute ~/.cache/storytold-craft-fonts-dl/deb/build/storytold-craft-fonts_*.deb
set -euo pipefail
# -h/--help: the comment at the top of this file, before anything else is read or done.
for a in "$@"; do
    case "$a" in -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done
# --no-clean: accepted so that every build.sh takes it, and a no-op here: nothing is compiled, the package only depends on others.
args=()
for a in "$@"; do
    if [ "$a" = --no-clean ]; then echo "--no-clean: no effect (nothing to keep)" >&2; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}
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
    echo "usage: $0 build [--no-clean]" >&2
    exit 2
    ;;
esac
