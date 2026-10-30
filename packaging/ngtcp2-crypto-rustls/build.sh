#!/bin/bash
# Build the ngtcp2 crypto helper for Rustls (libngtcp2_crypto_rustls) from Ubuntu's ngtcp2 source (the helper
# needs crypto/shared.c and a few headers of ngtcp2) and src/ in this directory.
#
#   build.sh fetch   download ngtcp2's orig tarball with `apt-get source` (the archive's signatures vouch for it)
#   build.sh build   fresh unpack, overlay src/ and debian/, build
#
# Layout: ~/.cache/ngtcp2-crypto-rustls-dl/{orig,deb/build}. The debs end up in deb/build/. Add them with
#   sgl-reprepro includedeb resolute-testing ~/.cache/ngtcp2-crypto-rustls-dl/deb/build/*_<version>-*.deb
# The build needs librustls-quic-dev and libngtcp2-dev installed (see Build-Depends): for the first one, add the
# repository's resolute-testing suite or install the deb by hand.
# SGL_RUSTLS_QUIC_PREFIX=<dir> builds against the dev files of librustls-quic that are only unpacked there (a prefix with
# usr/ of both debs, the prefix= of rustls-quic.pc pointing at it) and not installed: needed when the new librustls-quic
# Breaks the installed helper, which installing it would take out together with what depends on it (curl). The
# dependency check of dpkg-buildpackage is skipped then (-d), so the Depends of debian/control must name the version.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cmd=${1:-}
version=1.16.0
dl=$HOME/.cache/ngtcp2-crypto-rustls-dl
orig=$dl/orig/ngtcp2_$version.orig.tar.xz
bd=$dl/deb/build
work=$bd/ngtcp2-crypto-rustls-$version

# Empty environment, as for the other packages (see curl-build.md).
build_env() {
    env -i HOME="$HOME" LOGNAME="${LOGNAME:-$USER}" USER="${USER:-$LOGNAME}" LANG=C.UTF-8 TERM="${TERM:-dumb}" \
        PATH="/usr/sbin:/usr/bin:/sbin:/bin" \
        PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
        "$@"
}

case "$cmd" in
fetch)
    mkdir -p "$dl/orig"
    cd "$dl/orig"
    apt-get source --download-only ngtcp2 >/dev/null
    [ -f "$orig" ] || { echo "no ngtcp2_$version.orig.tar.xz after apt-get source: another version?" >&2; exit 1; }
    ls -l "$dl/orig"
    ;;
build)
    [ -f "$orig" ] || { echo "run '$0 fetch' first" >&2; exit 1; }
    mkdir -p "$bd"
    cp -f "$orig" "$bd/ngtcp2-crypto-rustls_$version.orig.tar.xz"
    rm -rf "$work"
    mkdir -p "$work"
    tar -xJf "$bd/ngtcp2-crypto-rustls_$version.orig.tar.xz" -C "$work" --strip-components=1
    mkdir -p "$work/crypto/rustls"
    cp "$here"/src/* "$work/crypto/rustls/"
    rsync -a "$here/debian/" "$work/debian/"
    cd "$work"
    if [ -n "${SGL_RUSTLS_QUIC_PREFIX:-}" ]; then
        build_env PKG_CONFIG_PATH="$SGL_RUSTLS_QUIC_PREFIX/usr/lib/x86_64-linux-gnu/pkgconfig" \
            DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -us -uc -b -d
    else
        build_env DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -us -uc -b
    fi
    echo "debs are in $bd"
    ;;
*)
    echo "usage: $0 fetch|build" >&2
    exit 2
    ;;
esac
