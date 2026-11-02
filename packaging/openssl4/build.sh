#!/bin/bash
# Rebuild libssl4 (OpenSSL 4, runtime libraries only) from Ubuntu's openssl source for stonking, on resolute.
#
#   build.sh fetch [version]   download Ubuntu's source package (orig tarball + signature) into
#                              ~/.cache/openssl4-dl/orig/ and verify the tarball against OpenSSL's release key
#                              (debian/upstream/signing-key.asc, throw-away GNUPGHOME)
#   build.sh build [version]   unpack the tarball afresh, copy debian/ into it and build libssl4
#
# <version> is the upstream version (default 4.0.3); the Ubuntu revision is the one in debian/changelog.
# debian/ in this directory is the source of truth; the work tree is thrown away on every build.
# The deb ends up in ~/.cache/openssl4-dl/deb/build/. Add it with:
#   sgl-reprepro includedeb resolute ~/.cache/openssl4-dl/deb/build/libssl4_*.deb
# (see ~/.local/share/apt/docs/openssl4-build.md)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cmd=${1:-}
version=${2:-4.0.3}
ubuntu_rev=1ubuntu1
dl=$HOME/.cache/openssl4-dl
orig=$dl/orig/openssl_$version.orig.tar.gz
bd=$dl/deb/build
work=$bd/openssl-$version

case "$cmd" in
fetch)
    mkdir -p "$dl/orig"
    cd "$dl/orig"
    # pull-lp-source verifies the .dsc and the files against Launchpad's checksums.
    if [ ! -f "$orig" ] || [ ! -f "$orig.asc" ]; then
        pull-lp-source --download-only openssl "$version-$ubuntu_rev"
    fi
    gh=$(mktemp -d "$dl/gnupg.XXXXXX")
    trap 'rm -rf "$gh"' EXIT
    chmod 700 "$gh"
    GNUPGHOME=$gh gpg --quiet --import "$here/debian/upstream/signing-key.asc"
    out=$(GNUPGHOME=$gh gpg --status-fd 1 --verify "$orig.asc" "$orig" 2>&1)
    grep -q '^\[GNUPG:\] GOODSIG ' <<<"$out" && grep -q '^\[GNUPG:\] VALIDSIG ' <<<"$out" \
        || { echo "signature check failed:" >&2; echo "$out" >&2; exit 1; }
    echo "verified $(basename "$orig")"
    grep '^\[GNUPG:\] VALIDSIG ' <<<"$out" | cut -d' ' -f3
    ;;
build)
    [ -f "$orig" ] && [ -f "$orig.asc" ] || { echo "run '$0 fetch $version' first" >&2; exit 1; }
    mkdir -p "$bd"
    cp -f "$orig" "$bd/openssl_$version.orig.tar.gz"
    cp -f "$orig.asc" "$bd/openssl_$version.orig.tar.gz.asc"
    rm -rf "$work"
    tar -xzf "$bd/openssl_$version.orig.tar.gz" -C "$bd"
    rsync -a "$here/debian/" "$work/debian/"
    cd "$work"
    # Start from an empty environment, like a real builder: the login shell exports LD_RUN_PATH
    # (ld turns it into RUNPATH), LD_LIBRARY_PATH, LIBRARY_PATH and PKG_CONFIG_PATH, and /usr/local must not leak in.
    # nocheck: the test suite takes long; the checks that matter are made on the built deb (see the notes).
    env -i \
        HOME="$HOME" LOGNAME="${LOGNAME:-$USER}" USER="${USER:-$LOGNAME}" LANG=C.UTF-8 TERM="${TERM:-dumb}" \
        PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
        DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
        dpkg-buildpackage -us -uc -b
    echo "debs are in $bd"
    ;;
*)
    echo "usage: $0 fetch|build [version]" >&2
    exit 2
    ;;
esac
