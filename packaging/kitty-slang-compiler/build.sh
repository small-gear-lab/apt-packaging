#!/bin/bash
# Build the kitty-slang-compiler .deb from the official Slang release archive.
#
# Usage: build.sh [slang-version] [smallgearlab-number]
#        build.sh 2026.14.1 2        ->  kitty-slang-compiler_2026.14.1-1~smallgearlab2_amd64.deb
#
# Why this package exists: kitty needs a newer slangc than Ubuntu ships (see
# ~/.local/share/apt/docs/kitty-build.md). Everything is installed under
# /usr/lib/kitty-slang-compiler/ and nothing is put on PATH, so Ubuntu's
# slang-compiler is not affected.
#
# The archive is the glibc-2.27 build from https://github.com/shader-slang/slang/releases.
# It is checked against the sha256 digest GitHub reports for the asset.
set -euo pipefail

version=${1:-2026.14.1}
number=${2:-1}
deb_version="${version}-1~smallgearlab${number}"
asset="slang-${version}-linux-x86_64-glibc-2.27.tar.gz"
prefix=usr/lib/kitty-slang-compiler
work=$HOME/.cache/kitty-dl/slang-build/$version
maintainer='small-gear-lab <289302950+marie-222@users.noreply.github.com>'

mkdir -p "$work/dl"

echo "== download $asset"
gh release download "v$version" -R shader-slang/slang -p "$asset" -D "$work/dl" --clobber
expected=$(gh api "repos/shader-slang/slang/releases/tags/v$version" \
    --jq ".assets[] | select(.name==\"$asset\") | .digest")
actual=sha256:$(sha256sum "$work/dl/$asset" | cut -d' ' -f1)
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "digest mismatch: expected '$expected', got '$actual'" >&2
    exit 1
fi
echo "digest ok: $actual"

echo "== extract"
rm -rf "$work/src" "$work/root" "$work/test"
mkdir -p "$work/src" "$work/root/DEBIAN"
tar -xzf "$work/dl/$asset" -C "$work/src"
src=$work/src
root=$work/root

echo "== stage"
install -d -m 755 "$root/$prefix/bin" "$root/$prefix/lib" "$root/usr/share/doc/kitty-slang-compiler"
install -m 755 "$src/bin/slangc" "$root/$prefix/bin/slangc"
# Only what slangc loads: the compiler library and the two modules next to it.
cp -a "$src"/lib/libslang-compiler.so* "$src"/lib/libslang-glsl-module-*.so \
      "$src"/lib/libslang-glslang-*.so "$root/$prefix/lib/"
if [ -d "$src/lib/slang-standard-module-$version" ]; then
    cp -a "$src/lib/slang-standard-module-$version" "$root/$prefix/lib/"
fi
cp -a "$src/LICENSE" "$src/LICENSES" "$root/usr/share/doc/kitty-slang-compiler/"

cat > "$root/usr/share/doc/kitty-slang-compiler/copyright" <<EOF
Source: https://github.com/shader-slang/slang (release v$version, $asset)

The files in /usr/lib/kitty-slang-compiler/ are the unmodified Slang binaries of that
release. Slang itself is licensed under Apache-2.0 WITH LLVM-exception. The release also
contains third-party components under the licenses collected in LICENSES/.

The full texts shipped with the release are in this directory:
  LICENSE      the Slang license
  LICENSES/    the license texts of Slang and of the bundled components

This copy was not checked for components whose licenses are missing from LICENSES/.
EOF

cat > "$root/usr/share/doc/kitty-slang-compiler/README.Debian" <<EOF
kitty-slang-compiler
--------------------
slangc $version from the official Slang release, installed under
/usr/lib/kitty-slang-compiler/ only.

kitty 0.49 expects slang 2026.14.1 (bypy/sources.json in the kitty source), which is newer
than the slang-compiler package of Ubuntu 26.04 (2026.1.1). The older compiler emits GLSL that
Mesa rejects, so kitty is built with SLANGC pointing at this copy. Nothing is put on PATH.
EOF

cat > "$root/DEBIAN/control" <<EOF
Package: kitty-slang-compiler
Version: $deb_version
Architecture: amd64
Maintainer: $maintainer
Section: devel
Priority: optional
Depends: libc6 (>= 2.27), libstdc++6, libgcc-s1
Description: Slang shader compiler (slangc) used to build kitty
 The official Slang $version release (slangc and its libraries), installed under
 /usr/lib/kitty-slang-compiler/ only. kitty 0.49 needs a newer slang than Ubuntu
 provides to generate GLSL that Mesa accepts.
EOF

find "$root" -type d -exec chmod 755 {} +
find "$root" -type f ! -perm /111 -exec chmod 644 {} +

echo "== build"
mkdir -p "$work/out"
deb="$work/out/kitty-slang-compiler_${deb_version}_amd64.deb"
dpkg-deb --root-owner-group --build "$root" "$deb"

echo "== smoke test (empty environment)"
mkdir -p "$work/test/x"
dpkg-deb -x "$deb" "$work/test/x"
cat > "$work/test/t.slang" <<'EOF'
[shader("vertex")]
float4 main(float3 p : POSITION) : SV_Position { return float4(p, 1.0); }
EOF
env -i PATH=/usr/bin:/bin "$work/test/x/$prefix/bin/slangc" "$work/test/t.slang" \
    -target glsl -entry main -stage vertex -o "$work/test/out.glsl"
test -s "$work/test/out.glsl"
echo "slangc compiled a test shader ($(wc -c < "$work/test/out.glsl") bytes)"

echo "== done"
echo "$deb"
