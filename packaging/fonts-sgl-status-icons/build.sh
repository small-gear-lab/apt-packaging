#!/bin/bash
# Build the fonts-sgl-status-icons .deb (the SGL Status Icons font used by kitty's sgl__program_status_symbol).
#
# Usage: build.sh [--regen] [version] [debian-revision]
#        build.sh                     ->  fonts-sgl-status-icons_1.0.0-1_all.deb
#        build.sh --regen 1.0.1 1     ->  redo outline/ from src/ first (needs inkscape)
#
# src/*.svg      the drawings (viewBox 0 0 100 100, black fill/stroke). Edit these.
# outline/*.svg  the same with strokes turned into outlines, because fontforge ignores strokes.
#                Committed, so building needs only fontforge; --regen redoes them with inkscape.
# Glyph list and metrics: build-font.py. Output goes to ~/.cache/fonts-sgl-status-icons-build/.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
regen=0
if [ "${1:-}" = "--regen" ]; then regen=1; shift; fi
version=${1:-1.0.0}
revision=${2:-1}
pkg=fonts-sgl-status-icons
work=$HOME/.cache/$pkg-build
maintainer='small-gear-lab <289302950+marie-222@users.noreply.github.com>'

if [ "$regen" = 1 ]; then
    echo "== outlines (inkscape)"
    for svg in "$here"/src/*.svg; do
        inkscape "$svg" --actions="select-all:all;object-to-path;object-stroke-to-path;export-filename:$here/outline/$(basename "$svg" .svg)-outline.svg;export-do"
    done
fi

echo "== font (fontforge)"
rm -rf "$work"
mkdir -p "$work/root/DEBIAN" "$work/root/usr/share/fonts/truetype/sgl-status-icons" "$work/root/usr/share/doc/$pkg"
fontforge -lang=py -script "$here/build-font.py" "$here/outline" \
    "$work/root/usr/share/fonts/truetype/sgl-status-icons/SglStatusIcons-Regular.ttf" "$version" 2>&1 | rg -v '^(PythonUI_Init|copyUIMethodsToBaseTable|Program root|Copyright|License|Version|Based on)' || true

cat > "$work/root/usr/share/doc/$pkg/copyright" <<COPY
Copyright: 2026 small-gear-lab
Glyphs and font: drawn for personal use on this machine.
No license for redistribution is granted. Built with FontForge from the drawings in the packaging directory.
COPY
cat > "$work/root/usr/share/doc/$pkg/README.Debian" <<README
fonts-sgl-status-icons
----------------------
Family "SGL Status Icons" (private use area, Nerd Fonts leaves U+E900-E9FF free):
  U+E900  pause (idle)        U+E901  moon and z (idle, alternative)        U+E902  hand (blocked)
Used from kitty.conf with the local option of the small-gear-lab kitty package, e.g.
  sgl__program_status_symbol idle U+E900 #d9bf6a SGL Status Icons
A running kitty keeps the old font in memory: restart it after upgrading this package.
README

cat > "$work/changelog" <<LOG
$pkg ($version-$revision) resolute; urgency=medium

  * Glyphs for the sgl__program_status_symbol option of the kitty
    package: pause, moon and z, hand.

 -- $maintainer  $(date -R)
LOG
gzip -9n -c "$work/changelog" > "$work/root/usr/share/doc/$pkg/changelog.Debian.gz"
rm "$work/changelog"

size=$(du -sk "$work/root/usr" | cut -f1)
cat > "$work/root/DEBIAN/control" <<CTRL
Package: $pkg
Version: $version-$revision
Section: fonts
Priority: optional
Architecture: all
Multi-Arch: foreign
Installed-Size: $size
Maintainer: $maintainer
Description: status icons for kitty's program status (SGL Status Icons)
 A tiny font with the glyphs drawn for the sgl__program_status_symbol
 option of the small-gear-lab kitty package. Same box as Symbols Nerd
 Font Mono, in the private use area U+E900-E9FF.
CTRL

find "$work/root" -type d -exec chmod 755 {} +
find "$work/root/usr" -type f -exec chmod 644 {} +
deb="$work/${pkg}_${version}-${revision}_all.deb"
dpkg-deb --root-owner-group --build "$work/root" "$deb"
dpkg-deb -c "$deb"
echo "built $deb"
