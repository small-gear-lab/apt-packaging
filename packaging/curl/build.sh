#!/bin/bash
# Rebuild the curl debs (OpenSSL and Rustls flavours, HTTP/3 via ngtcp2 + nghttp3) from this directory's debian/.
#
#   build.sh fetch [version]   download the upstream tarball and its signature into ~/.cache/curl-dl/orig/
#                              and verify it against Daniel Stenberg's key (throw-away GNUPGHOME)
#   build.sh check-copyright [version]
#                              check debian/copyright against the source of that version (check-copyright.py)
#   build.sh build [version] [--no-clean]
#                              unpack the tarball afresh (or, with --no-clean, keep the work tree of the last
#                              build), check debian/copyright, copy debian/ into it and build the debs
#
# debian/ in this directory is the source of truth; the work tree is thrown away on every build.
# The debs end up in ~/.cache/curl-dl/deb/build/. Add them with:
#   sgl-reprepro includedeb resolute-testing ~/.cache/curl-dl/deb/build/*_<version>-*.deb
# (see ~/.local/share/apt/docs/curl-build.md)
set -euo pipefail
# -h/--help: the comment at the top of this file, before anything else is read or done.
for a in "$@"; do
    case "$a" in -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done

here=$(cd "$(dirname "$0")" && pwd)
# --no-clean (build only): keep the work tree of the last build (the unpacked source and its build output), so that
# only what changed is compiled again. Use it when the binaries do not need to be rebuilt (a change to debian/control
# or debian/changelog, say). debian/ is always synced from this directory, also in a kept tree.
noclean=0
args=()
for a in "$@"; do
    if [ "$a" = --no-clean ]; then noclean=1; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}
nc=()
[ "$noclean" = 1 ] && nc=(-nc)
cmd=${1:-}
version=${2:-8.23.0}
dl=$HOME/.cache/curl-dl
orig=$dl/orig/curl-$version.tar.xz
bd=$dl/deb/build
work=$bd/curl-$version

# curl's signing key (fingerprint published at https://daniel.haxx.se/mykey.asc).
key_fpr=27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2

case "$cmd" in
fetch)
    mkdir -p "$dl/orig"
    cd "$dl/orig"
    for f in "curl-$version.tar.xz" "curl-$version.tar.xz.asc"; do
        [ -f "$f" ] || env -u LD_LIBRARY_PATH /usr/bin/curl -fsSLO "https://curl.se/download/$f"
    done
    gh=$(mktemp -d "$dl/gnupg.XXXXXX")
    trap 'rm -rf "$gh"' EXIT
    chmod 700 "$gh"
    env -u LD_LIBRARY_PATH /usr/bin/curl -fsS https://daniel.haxx.se/mykey.asc | GNUPGHOME=$gh gpg --quiet --import
    out=$(GNUPGHOME=$gh gpg --status-fd 1 --verify "curl-$version.tar.xz.asc" "curl-$version.tar.xz" 2>&1)
    grep -q '^\[GNUPG:\] GOODSIG ' <<<"$out" && grep -q "^\[GNUPG:\] VALIDSIG $key_fpr " <<<"$out" \
        || { echo "signature check failed:" >&2; echo "$out" >&2; exit 1; }
    echo "verified curl-$version.tar.xz (key $key_fpr)"
    ;;
build)
    [ -f "$orig" ] && [ -f "$orig.asc" ] || { echo "run '$0 fetch $version' first" >&2; exit 1; }
    mkdir -p "$bd"
    cp -f "$orig" "$bd/curl_$version.orig.tar.xz"
    cp -f "$orig.asc" "$bd/curl_$version.orig.tar.xz.asc"
    kept=0
    if [ "$noclean" = 1 ] && [ -d "$work" ]; then
        kept=1
        echo "--no-clean: reusing the work tree $work"
    else
        rm -rf "$work"
        tar -xJf "$bd/curl_$version.orig.tar.xz" -C "$bd"
    fi
    # debian/copyright must still describe this version of the source; stop when it does not.
    if [ "$kept" = 1 ]; then
        # A kept tree holds the build output (debian/build-openssl, debian/build-rustls), which the check would
        # read as source: check against a clean unpack of the tarball instead.
        ctmp=$(mktemp -d "$dl/check.XXXXXX")
        tar -xJf "$orig" -C "$ctmp"
        python3 -I "$here/check-copyright.py" "$ctmp/curl-$version" "$here/debian/copyright" || { rm -rf "$ctmp"; exit 1; }
        rm -rf "$ctmp"
    else
        python3 -I "$here/check-copyright.py" "$work" "$here/debian/copyright"
    fi
    # The two build directories are curl's build output (it builds out of tree, inside debian/): keep them, or a
    # kept tree would be built from nothing. Everything else of debian/ is synced, debhelper's own state included.
    rsync -a --delete --exclude='/build-openssl/' --exclude='/build-rustls/' "$here/debian/" "$work/debian/"
    cd "$work"
    # Start from an empty environment, like a real builder. The login shell exports LD_RUN_PATH
    # (ld turns it into RUNPATH: lintian's custom-library-search-path), LD_LIBRARY_PATH, LIBRARY_PATH
    # and PKG_CONFIG_PATH, and unsetting them one by one misses the next one. /usr/local must not leak in.
    # dpkg-source applies debian/patches (quilt) before the build.
    env -i \
        HOME="$HOME" LOGNAME="${LOGNAME:-$USER}" USER="${USER:-$LOGNAME}" LANG=C.UTF-8 TERM="${TERM:-dumb}" \
        PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
        DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" \
        dpkg-buildpackage -us -uc -b ${nc[@]+"${nc[@]}"}
    echo "debs are in $bd"
    ;;
check-copyright)
    [ -f "$orig" ] || { echo "run '$0 fetch $version' first" >&2; exit 1; }
    tmp=$(mktemp -d "$dl/check.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    tar -xJf "$orig" -C "$tmp"
    python3 -I "$here/check-copyright.py" "$tmp/curl-$version" "$here/debian/copyright"
    ;;
*)
    echo "usage: $0 fetch|build|check-copyright [version] [--no-clean]" >&2
    exit 2
    ;;
esac
