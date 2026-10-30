#!/bin/bash
# Keep the kitty packaging (debian/) outside ~/.cache and rebuild the debs from it.
#
#   build.sh save  [version]   copy debian/ from the work tree into this directory
#                              (run it after changing patches, rules, control or changelog there)
#   build.sh build [version]   copy debian/ from this directory into the work tree, fetch the font (below),
#                              write the license documents of the vendored Go modules (gen-vendor-licenses.py),
#                              clear the old build state and build the debs
#   build.sh fetch-font [ver]  take the Symbols Nerd Font out of kitty's signed release archive and gather
#                              the license documents of its Nerd Fonts release
#
# The work tree is ~/.cache/kitty-dl/deb/build/kitty-<version>/: the upstream source with
# `go mod vendor` already run (steps 1-4 of ~/.local/share/apt/docs/kitty-build.md).
# `build` expects the quilt patches in the tree to be in the same state as the ones in
# debian/patches (the usual case when only rebuilding). When a patch changed, edit it in the
# work tree with quilt, run `save`, then `build`.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cmd=${1:-}
version=${2:-0.49.2}
work=$HOME/.cache/kitty-dl/deb/build/kitty-$version

# The Symbols Nerd Font Mono. Ubuntu's source package carried a copy of it inside debian/ (Nerd Fonts v3.2.1,
# older than what kitty ships); it is not kept in this repository. Instead the font follows kitty: it is taken
# from kitty's own binary release archive for the version being built, which is what upstream chose
# (kitty 0.49.2 ships Nerd Fonts v3.3.0). The source tarball has no pin to read, and kitty's devenv fetches
# `latest`. The archive is signed by Kovid Goyal, so the signature is what makes the font trustworthy;
# nothing about the font is pinned here, and a new kitty version brings its own font. The license documents
# of the Nerd Fonts release that font comes from are fetched too and shipped next to it (see below); this
# directory keeps neither the font nor those documents.
kitty_dl=$HOME/.cache/kitty-dl/v$version
nerd_ttf=SymbolsNerdFontMono-Regular.ttf
nerd_cache=$HOME/.cache/kitty-dl/nerd-fonts/from-kitty-$version
kovid_fpr=3CE1780F78DD88DF45194FD706BC317B515ACE7C # Kovid Goyal (New longer key), signer of kitty's archives

nerd_notices=$nerd_cache/notices

# Which Nerd Fonts release is this font? The file in kitty's archive carries no version, so look for the
# release whose NerdFontsSymbolsOnly.tar.xz holds the identical file, newest first. The answer is cached.
find_nerd_release() {
    local sha=$1 tag
    if [ -f "$nerd_cache/tag" ]; then
        cat "$nerd_cache/tag"
        return 0
    fi
    for tag in $(gh api 'repos/ryanoasis/nerd-fonts/releases?per_page=30' --jq '.[] | select(.prerelease | not) | .tag_name'); do
        if [ "$(gh release download "$tag" -R ryanoasis/nerd-fonts -p NerdFontsSymbolsOnly.tar.xz -O - 2>/dev/null |
            tar -xJO "$nerd_ttf" 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$sha" ]; then
            echo "$tag" | tee "$nerd_cache/tag"
            return 0
        fi
    done
    return 1
}

# The license documents that belong to that release: the LICENSE inside the Symbols Only asset, and the
# repository's LICENSE (it carries the full SIL OFL text) and license-audit.md (the licenses of the glyph
# sets the font gathers) at the same tag. They travel with the font into the deb.
fetch_nerd_notices() {
    local tag=$1 asset=NerdFontsSymbolsOnly.tar.xz raw=https://raw.githubusercontent.com/ryanoasis/nerd-fonts/$1 tmp
    rm -rf "$nerd_notices"
    mkdir -p "$nerd_notices"
    tmp=$(mktemp -d "$nerd_cache/release.XXXXXX")
    gh release download "$tag" -R ryanoasis/nerd-fonts -p "$asset" -D "$tmp"
    tar -xJf "$tmp/$asset" -C "$nerd_notices" LICENSE
    rm -rf "$tmp"
    env -u LD_LIBRARY_PATH /usr/bin/curl -fsSL -o "$nerd_notices/NERD-FONTS-LICENSE" "$raw/LICENSE"
    env -u LD_LIBRARY_PATH /usr/bin/curl -fsSL -o "$nerd_notices/NERD-FONTS-LICENSE-AUDIT.md" "$raw/license-audit.md"
    cat > "$nerd_notices/NERD-FONTS-VERSION" <<EOF
$nerd_ttf is Nerd Fonts $tag (https://github.com/ryanoasis/nerd-fonts/releases/tag/$tag),
sha256 $(sha256sum "$nerd_cache/$nerd_ttf" | cut -d' ' -f1)
taken from the binary release archive of kitty $version, which carries the identical file.

LICENSE                      the license file of the NerdFontsSymbolsOnly release asset
NERD-FONTS-LICENSE           LICENSE of the Nerd Fonts repository at $tag (it carries the SIL OFL 1.1 text)
NERD-FONTS-LICENSE-AUDIT.md  license-audit.md of the repository at $tag: the licenses of the glyph sets
EOF
}

# Download kitty-<version>-x86_64.txz and its signature, verify it, take the font out of it, then gather the
# license documents of the Nerd Fonts release it comes from.
fetch_nerd_font() {
    local archive=kitty-$version-x86_64.txz url=https://github.com/kovidgoyal/kitty/releases/download/v$version f gh out sha tag
    if [ ! -f "$nerd_cache/$nerd_ttf" ]; then
        mkdir -p "$kitty_dl" "$nerd_cache"
        for f in "$archive" "$archive.sig"; do
            [ -f "$kitty_dl/$f" ] || env -u LD_LIBRARY_PATH /usr/bin/curl -fsSL -o "$kitty_dl/$f" "$url/$f"
        done
        gh=$(mktemp -d "$HOME/.cache/kitty-dl/gnupg.XXXXXX")
        chmod 700 "$gh"
        env -u LD_LIBRARY_PATH /usr/bin/curl -fsS https://calibre-ebook.com/signatures/kovid.gpg \
            | GNUPGHOME=$gh gpg --quiet --import
        out=$(GNUPGHOME=$gh gpg --status-fd 1 --verify "$kitty_dl/$archive.sig" "$kitty_dl/$archive" 2>&1 || true)
        rm -rf "$gh"
        if ! grep -q '^\[GNUPG:\] GOODSIG ' <<<"$out" || ! grep -q "^\[GNUPG:\] VALIDSIG $kovid_fpr " <<<"$out"; then
            echo "signature check of $archive failed:" >&2
            echo "$out" >&2
            exit 1
        fi
        tar -xJf "$kitty_dl/$archive" -C "$nerd_cache" --strip-components=3 "lib/kitty/fonts/$nerd_ttf" \
            || { echo "no $nerd_ttf in $archive" >&2; exit 1; }
    fi
    sha=$(sha256sum "$nerd_cache/$nerd_ttf" | cut -d' ' -f1)
    if [ ! -f "$nerd_notices/NERD-FONTS-VERSION" ]; then
        tag=$(find_nerd_release "$sha") || {
            echo "no Nerd Fonts release among the latest 30 holds this $nerd_ttf (sha256 $sha)." >&2
            echo "Find it by hand, then check its LICENSE and license-audit.md before shipping it." >&2
            exit 1
        }
        fetch_nerd_notices "$tag"
    fi
    echo "$nerd_ttf from $archive (signature ok): Nerd Fonts $(cat "$nerd_cache/tag"), sha256 ${sha:0:16}"
}

# Build output inside debian/ that must not be saved (and must survive the sync).
excludes=(
    --exclude='/.debhelper/' --exclude='/debhelper-build-stamp' --exclude='/files'
    --exclude='/tmp/' --exclude='/fakehome/' --exclude='/fakeruntime/' --exclude='/gocache/' --exclude='/gopath/'
    --exclude='/kitty/' --exclude='/kitty-doc/' --exclude='/kitty-terminfo/' --exclude='/kitty-shell-integration/'
    --exclude='*.debhelper.log' --exclude='*.substvars' --exclude='*.debhelper'
    --exclude='/external/' --exclude='/vendor-licenses/'
)

case "$cmd" in
save)
    [ -d "$work/debian" ] || { echo "no debian/ in $work" >&2; exit 1; }
    mkdir -p "$here/debian"
    # debian/copyright in the work tree is the generated one (base + the Go modules, see `build`): never save it
    # over the base. Edit the base in this directory.
    rsync -a --delete "${excludes[@]}" --exclude='/copyright' "$work/debian/" "$here/debian/"
    echo "saved $work/debian -> $here/debian"
    ;;
build)
    [ -d "$work" ] || { echo "no source tree at $work (see kitty-build.md, steps 1-4)" >&2; exit 1; }
    rsync -a --delete "${excludes[@]}" "$here/debian/" "$work/debian/"
    fetch_nerd_font
    install -d "$work/debian/external/fonts"
    install -m 644 "$nerd_cache/$nerd_ttf" "$nerd_notices"/* "$work/debian/external/fonts/"
    # The Go modules linked into kitten: copy their license files into debian/vendor-licenses/ (debian/kitty.docs
    # installs them) and write debian/copyright as the base copyright plus a paragraph per module. It stops the
    # build for a module whose license it cannot settle.
    python3 -I "$here/gen-vendor-licenses.py" "$work" "$here/debian/copyright" \
        "$here/vendor-license-overrides.tsv" "$here/vendor-holders.tsv"
    cd "$work"
    # debhelper skips the build step when it finds its stamps, so clear them first.
    rm -rf build linux-package debian/.debhelper debian/tmp debian/debhelper-build-stamp debian/files
    for d in kitty kitty-doc kitty-terminfo kitty-shell-integration; do rm -rf "debian/$d"; done
    # An empty environment, like a real builder: the login shell exports LD_RUN_PATH (ld turns it into
    # RUNPATH /usr/local/lib), LD_LIBRARY_PATH, LIBRARY_PATH, PKG_CONFIG_PATH and a pyenv PATH, and
    # unsetting them one by one misses the next one. Only the system pkg-config directories are used:
    # /usr/local holds stale .pc files. SLANGC is set in debian/rules; -nc keeps vendor/.
    env -i \
        HOME="$HOME" LOGNAME="${LOGNAME:-$USER}" USER="${USER:-$LOGNAME}" LANG=C.UTF-8 TERM="${TERM:-dumb}" \
        PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
        DEB_BUILD_OPTIONS=nocheck \
        dpkg-buildpackage -us -uc -b -nc
    echo "debs are in $(dirname "$work")"
    ;;
fetch-font)
    fetch_nerd_font
    echo "font: $nerd_cache/$nerd_ttf (notices: $nerd_notices)"
    ;;
*)
    echo "usage: $0 save|build|fetch-font [version]" >&2
    exit 2
    ;;
esac
