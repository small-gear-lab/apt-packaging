#!/bin/bash
# Build the neovim debs (neovim, neovim-runtime) of a newer upstream release on top of Ubuntu's packaging.
#
# Usage: build.sh [--no-clean] [version]
#        build.sh                 ->  builds 0.12.6 with the debian/ in this directory
#        build.sh --no-clean      ->  keeps build/ of the work tree (recompile only what changed)
#
# What it does:
#   1. downloads the upstream source of v<version> and checks it: the commit id embedded in the GitHub tarball
#      must equal the commit the tag points to (asked of the GitHub API with gh);
#   2. reads cmake.deps/deps.txt of that source and downloads the tree-sitter grammars upstream pins
#      (c lua vim vimdoc query markdown), each checked against the sha256 in deps.txt, into
#      debian/external/ts/<lang>/ together with their LICENSE files (debian/external/ts-licenses/);
#   3. builds with dpkg-buildpackage in an empty environment (the login shell exports LD_RUN_PATH & co,
#      which leak a RUNPATH into the binaries).
#
# The packaging (debian/) is Ubuntu's neovim 0.11.6-1 minus the test suite and minus the
# tree-sitter-*-src build dependencies (older than what the 0.12 runtime queries expect).
# The version in debian/changelog must match <version>; bump the ~smallgearlab number there.
# The work tree is ~/.cache/nvim-dl/build/neovim-<version>/ (disposable); debs land in its parent.
set -euo pipefail
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
version=${1:-0.12.6}
dl=$HOME/.cache/nvim-dl/dl
root=$HOME/.cache/nvim-dl/build
work=$root/neovim-$version
curl() { env -u LD_LIBRARY_PATH /usr/bin/curl -fsSL "$@"; }

if ! sed -n 1p "$here/debian/changelog" | grep -q "^neovim ($version-"; then
    echo "debian/changelog does not start with neovim ($version-...)" >&2
    exit 1
fi

mkdir -p "$dl" "$root"

# 1. upstream source
tarball=$dl/neovim-$version.tar.gz
[ -f "$tarball" ] || curl -o "$tarball" "https://github.com/neovim/neovim/archive/refs/tags/v$version.tar.gz"
# get-tar-commit-id stops reading after the header, so gzip gets SIGPIPE: not an error here.
embedded=$(set +o pipefail; gzip -dc "$tarball" | git get-tar-commit-id)
ref=$(gh api "repos/neovim/neovim/git/ref/tags/v$version" --jq '.object.type + " " + .object.sha')
if [ "${ref%% *}" = tag ]; then
    tagged=$(gh api "repos/neovim/neovim/git/tags/${ref#* }" --jq .object.sha)
else
    tagged=${ref#* }
fi
if [ "$embedded" != "$tagged" ]; then
    echo "source tarball commit $embedded != tag commit $tagged" >&2
    exit 1
fi
echo "source ok: v$version = $tagged"

if [ "$noclean" = 0 ]; then rm -rf "$work"; fi
if [ ! -d "$work" ]; then
    mkdir -p "$work"
    tar -xzf "$tarball" -C "$work" --strip-components=1
fi

# 2. the tree-sitter grammars upstream pins
deps=$work/cmake.deps/deps.txt
ext=$work/debian/external
rm -rf "$ext"
mkdir -p "$ext/ts" "$ext/ts-licenses"
for lang in c lua vim vimdoc query markdown; do
    key=TREESITTER_$(echo "$lang" | tr a-z A-Z)
    url=$(sed -n "s/^${key}_URL //p" "$deps")
    sha=$(sed -n "s/^${key}_SHA256 //p" "$deps")
    [ -n "$url" ] && [ -n "$sha" ] || { echo "no $key in deps.txt" >&2; exit 1; }
    f=$dl/ts-$lang-$(basename "$url")
    [ -f "$f" ] || curl -o "$f" "$url"
    if [ "$(sha256sum "$f" | cut -d' ' -f1)" != "$sha" ]; then
        echo "sha256 mismatch for $lang ($url)" >&2
        exit 1
    fi
    mkdir -p "$ext/ts/$lang"
    tar -xzf "$f" -C "$ext/ts/$lang" --strip-components=1
    lic=$(find "$ext/ts/$lang" -maxdepth 1 -iname 'LICENSE*' | sort | sed -n '1p')
    [ -n "$lic" ] || { echo "no LICENSE in $lang grammar" >&2; exit 1; }
    cp "$lic" "$ext/ts-licenses/tree-sitter-$lang-LICENSE"
    echo "grammar ok: $lang ($(basename "$url"))"
done
# vimdoc grammar of the markdown tarball: two grammars under one tree
[ -d "$ext/ts/markdown/tree-sitter-markdown/src" ] && [ -d "$ext/ts/markdown/tree-sitter-markdown-inline/src" ]

# 3. build
rsync -a --delete --exclude='/external/' --exclude='/tmp/' --exclude='/.debhelper/' --exclude='/files' \
    --exclude='*.substvars' --exclude='*.debhelper*' --exclude='/neovim/' --exclude='/neovim-runtime/' \
    --exclude='/debhelper-build-stamp' "$here/debian/" "$work/debian/"
cd "$work"
if [ "$noclean" = 1 ]; then echo "--no-clean: keeping build/"; else rm -rf build; fi
rm -rf debian/.debhelper debian/tmp debian/debhelper-build-stamp debian/files debian/neovim debian/neovim-runtime
env -i \
    HOME="$HOME" LOGNAME="${LOGNAME:-$USER}" USER="${USER:-$LOGNAME}" LANG=C.UTF-8 TERM="${TERM:-dumb}" \
    PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
    DEB_BUILD_OPTIONS=nocheck \
    dpkg-buildpackage -us -uc -b -nc
echo "debs are in $root"
