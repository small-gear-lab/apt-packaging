#!/bin/bash
# Build the neovide .deb from the official Neovide release binary.
#
# Usage: build.sh [--no-clean] [neovide-version] [smallgearlab-number]
#        (--no-clean is accepted for the same interface as the other build.sh and changes nothing)
#        build.sh 0.17.2 1        ->  neovide_0.17.2-1~smallgearlab1_amd64.deb
#
# The binary is neovide-linux-x86_64.tar.gz of https://github.com/neovide/neovide/releases, checked against the
# sha256 digest GitHub reports for the asset. The desktop entry, the icons and the license come from the source
# at the same tag (the tarball's embedded commit id must equal the commit the tag points to).
# It is a repack, not a source build: the binary is statically linked Rust, so the crates inside it keep their
# own licenses, which are not enumerated here (see debian copyright in the package).
set -euo pipefail
for a in "$@"; do
    case "$a" in -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done
args=()
for a in "$@"; do
    if [ "$a" = --no-clean ]; then echo "--no-clean: no effect (nothing to keep)" >&2; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}

version=${1:-0.17.2}
number=${2:-1}
deb_version="${version}-1~smallgearlab${number}"
asset=neovide-linux-x86_64.tar.gz
work=$HOME/.cache/nvim-dl/neovide/build-$version
maintainer='small-gear-lab <289302950+marie-222@users.noreply.github.com>'
curl() { env -u LD_LIBRARY_PATH /usr/bin/curl -fsSL "$@"; }

rm -rf "$work"
mkdir -p "$work/dl" "$work/src" "$work/bin" "$work/root/DEBIAN" "$work/out"

echo "== download $asset"
gh release download "$version" -R neovide/neovide -p "$asset" -D "$work/dl" --clobber
expected=$(gh api "repos/neovide/neovide/releases/tags/$version" --jq ".assets[] | select(.name==\"$asset\") | .digest")
actual=sha256:$(sha256sum "$work/dl/$asset" | cut -d' ' -f1)
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "digest mismatch: expected '$expected', got '$actual'" >&2
    exit 1
fi
echo "digest ok: $actual"
tar -xzf "$work/dl/$asset" -C "$work/bin"
[ -f "$work/bin/neovide" ] || { echo "no neovide binary in $asset" >&2; exit 1; }

echo "== source at the tag (desktop entry, icons, license)"
curl -o "$work/dl/src.tar.gz" "https://github.com/neovide/neovide/archive/refs/tags/$version.tar.gz"
# get-tar-commit-id stops reading after the header, so gzip gets SIGPIPE: not an error here.
embedded=$(set +o pipefail; gzip -dc "$work/dl/src.tar.gz" | git get-tar-commit-id)
ref=$(gh api "repos/neovide/neovide/git/ref/tags/$version" --jq '.object.type + " " + .object.sha')
if [ "${ref%% *}" = tag ]; then
    tagged=$(gh api "repos/neovide/neovide/git/tags/${ref#* }" --jq .object.sha)
else
    tagged=${ref#* }
fi
[ "$embedded" = "$tagged" ] || { echo "source tarball commit $embedded != tag commit $tagged" >&2; exit 1; }
echo "source ok: $version = $tagged"
tar -xzf "$work/dl/src.tar.gz" -C "$work/src" --strip-components=1

root=$work/root
echo "== stage"
install -d -m 755 "$root/usr/bin" "$root/usr/share/applications" "$root/usr/share/doc/neovide" \
    "$root/usr/share/icons/hicolor/scalable/apps"
install -m 755 "$work/bin/neovide" "$root/usr/bin/neovide"
install -m 644 "$work/src/assets/neovide.desktop" "$root/usr/share/applications/neovide.desktop"
install -m 644 "$work/src/assets/neovide.svg" "$root/usr/share/icons/hicolor/scalable/apps/neovide.svg"
for s in 16x16 32x32 48x48 256x256; do
    install -D -m 644 "$work/src/assets/neovide-$s.png" "$root/usr/share/icons/hicolor/$s/apps/neovide.png"
done
install -m 644 "$work/src/LICENSE" "$root/usr/share/doc/neovide/LICENSE"
gzip -9n -c > "$root/usr/share/doc/neovide/changelog.Debian.gz" <<EOF
neovide ($deb_version) resolute; urgency=medium

  * Repack of the official $asset of Neovide $version.

 -- $maintainer  $(date -R)
EOF

cat > "$root/usr/share/doc/neovide/copyright" <<EOF
Source: https://github.com/neovide/neovide (release $version, $asset)

Files: *
Copyright: the Neovide authors
License: MIT
 The full text is in /usr/share/doc/neovide/LICENSE.

The binary is the unmodified official release build. It is statically linked and contains Rust crates
and other components under their own licenses; those licenses are not enumerated in this package.
EOF

cat > "$root/DEBIAN/control" <<EOF
Package: neovide
Version: $deb_version
Architecture: amd64
Maintainer: $maintainer
Section: editors
Priority: optional
Homepage: https://neovide.dev/
Depends: neovim (>= 0.10), libc6 (>= 2.35), libstdc++6 (>= 12), libgcc-s1, libfontconfig1,
 libwayland-client0, libwayland-egl1, libxkbcommon0, libxkbcommon-x11-0, libx11-6, libx11-xcb1, libxcursor1,
 libxi6, libxcb1, libegl1, libgl1
Description: No Nonsense Neovim Client in Rust
 Neovide is a GUI frontend for Neovim: GPU-accelerated rendering, smooth
 cursor and scroll animations, and ligature support.
 .
 This is a repack of the official release binary.
EOF

find "$root" -type d -exec chmod 755 {} +
find "$root" -type f ! -perm /111 -exec chmod 644 {} +

echo "== build"
deb="$work/out/neovide_${deb_version}_amd64.deb"
dpkg-deb --root-owner-group --build "$root" "$deb"
echo "== smoke test"
env -i PATH=/usr/bin:/bin "$root/usr/bin/neovide" --version
echo "== done"
echo "$deb"
