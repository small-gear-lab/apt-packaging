#!/bin/bash
# Build a patched neovide .deb from source: the Neovide source at a tag plus the patches in ./patches.
#
# Usage: build-patched.sh [neovide-version] [smallgearlab-number]
#        build-patched.sh 0.17.2 2   ->  neovide_0.17.2-1~smallgearlab2_amd64.deb
#
# The patches make --reuse-instance / --new-window / --chdir work on Linux (one process, one window per
# nvim session), fix drawing with several OpenGL windows and add neovide.cycle_window (focus the next window),
# neovide.open_window (open a window in a directory) and neovide.focus_route / g:neovide_route_id (focus a chosen window).
# They are written against 0.17.2. winit-patches/ holds a patch for winit 0.30.13 (Wayland: pass the key press
# serial with the activation token, so GNOME moves the focus instead of only showing a notification);
# the build uses a patched copy of winit through [patch.crates-io].
# The source is the tag's tarball, whose embedded commit id must equal the commit the tag points to.
# The Rust toolchain is the nightly pinned by the source's rust-toolchain.toml (rustup installs it on first
# use, about 700 MB under ~/.rustup). Cargo downloads the crates and skia's prebuilt binaries during the build.
# Meant for the resolute-testing suite; the repacked official binary (build.sh) stays the default.
set -euo pipefail
for a in "$@"; do
    case "$a" in -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done
here=$(cd "$(dirname "$0")" && pwd)
version=${1:-0.17.2}
number=${2:-2}
deb_version="${version}-1~smallgearlab${number}"
work=$HOME/.cache/nvim-dl/neovide/patched-$version
maintainer='small-gear-lab <289302950+marie-222@users.noreply.github.com>'
curl() { env -u LD_LIBRARY_PATH /usr/bin/curl -fsSL "$@"; }

rm -rf "$work"
mkdir -p "$work/dl" "$work/src" "$work/root/DEBIAN" "$work/out"

echo "== source at the tag"
curl -o "$work/dl/src.tar.gz" "https://github.com/neovide/neovide/archive/refs/tags/$version.tar.gz"
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

echo "== patches"
cd "$work/src"
git init -q . && git add -A >/dev/null && git -c user.name=build -c user.email=build@localhost commit -q -m base
for p in "$here"/patches/*.patch; do
    echo "  $(basename "$p")"
    git apply --index "$p"
done

echo "== winit (patched copy)"
cargo fetch --locked
winit_version=0.30.13
winit_src=$(ls -d "${CARGO_HOME:-$HOME/.cargo}"/registry/src/*/winit-$winit_version | sed -n 1p)
[ -d "$winit_src" ] || { echo "winit-$winit_version is not in the cargo registry" >&2; exit 1; }
cp -r "$winit_src" "$work/winit-$winit_version"
chmod -R u+w "$work/winit-$winit_version"
for p in "$here"/winit-patches/*.patch; do
    echo "  $(basename "$p")"
    patch -d "$work/winit-$winit_version" -p1 --no-backup-if-mismatch < "$p"
done
# [patch.crates-io] exists already (nvim-rs); add winit to it
sed -i "/^\[patch.crates-io\]/a winit = { path = \"$work/winit-$winit_version\" }" Cargo.toml

echo "== cargo build --release"
# Not --locked: pointing winit at a path changes its entry in Cargo.lock. The versions stay as locked.
cargo build --release

root=$work/root
echo "== stage"
install -d -m 755 "$root/usr/bin" "$root/usr/share/applications" "$root/usr/share/doc/neovide" \
    "$root/usr/share/icons/hicolor/scalable/apps"
install -m 755 target/release/neovide "$root/usr/bin/neovide"
install -m 644 assets/neovide.desktop "$root/usr/share/applications/neovide.desktop"
install -m 644 assets/neovide.svg "$root/usr/share/icons/hicolor/scalable/apps/neovide.svg"
for s in 16x16 32x32 48x48 256x256; do
    install -D -m 644 "assets/neovide-$s.png" "$root/usr/share/icons/hicolor/$s/apps/neovide.png"
done
install -m 644 LICENSE "$root/usr/share/doc/neovide/LICENSE"
install -d -m 755 "$root/usr/share/doc/neovide/patches"
install -m 644 "$here"/patches/*.patch "$root/usr/share/doc/neovide/patches/"
install -d -m 755 "$root/usr/share/doc/neovide/winit-patches"
install -m 644 "$here"/winit-patches/*.patch "$root/usr/share/doc/neovide/winit-patches/"
gzip -9n -c > "$root/usr/share/doc/neovide/changelog.Debian.gz" <<EOF
neovide ($deb_version) resolute; urgency=medium

  * Build of Neovide $version from source with patches: --reuse-instance, --new-window and --chdir on
    Linux, per-window OpenGL context switching, neovide.cycle_window, neovide.open_window,
    neovide.focus_route, and a winit patch for Wayland focus.

 -- $maintainer  $(date -R)
EOF

cat > "$root/usr/share/doc/neovide/copyright" <<EOF
Source: https://github.com/neovide/neovide (tag $version, with the patches in /usr/share/doc/neovide/patches)

Files: *
Copyright: the Neovide authors
License: MIT
 The full text is in /usr/share/doc/neovide/LICENSE.

The binary is statically linked and contains Rust crates and other components under their own licenses;
those licenses are not enumerated in this package.
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
Description: No Nonsense Neovim Client in Rust (multi-window patches)
 Neovide is a GUI frontend for Neovim: GPU-accelerated rendering, smooth
 cursor and scroll animations, and ligature support.
 .
 This build adds Linux support for --reuse-instance, --new-window and --chdir
 (several windows in one process), draws each OpenGL window in its own context and can move the
 focus between windows, open windows and focus a chosen one (neovide.cycle_window, open_window,
 focus_route; on Wayland through a patched winit).
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
