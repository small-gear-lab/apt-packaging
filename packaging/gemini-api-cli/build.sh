#!/bin/bash
# Build the gemini-api-cli .deb from the official gemini-api release archive.
#
# Usage: build.sh [--no-clean] [version] [smallgearlab-number]
#        (--no-clean is accepted for the same interface as the other build.sh and changes nothing)
#        build.sh 0.4.6 1        ->  gemini-api-cli_0.4.6-1~smallgearlab1_amd64.deb
#
# Why: Ubuntu has no package for the Gemini API CLI (https://github.com/google-gemini/gemini-api-cli).
# Its install.sh only downloads gemini-api_Linux_x86_64.tar.gz from the GitHub release and moves the
# binary into /usr/local/bin, so this package does the same step as a .deb (/usr/bin/gemini-api).
# The archive is checked against checksums.txt of the release and against the sha256 digest GitHub
# reports for the asset. The binary is a statically linked Go program (no runtime dependencies).
# It is a repack: the Go modules linked into the binary keep their own licenses, which are not
# enumerated here. The project itself is Apache-2.0 (LICENSE ships in the archive).
set -euo pipefail
for a in "$@"; do
    case "$a" in -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done
args=()
for a in "$@"; do
    if [ "$a" = --no-clean ]; then echo "--no-clean: no effect (nothing to keep)" >&2; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}

version=${1:-0.4.6}
number=${2:-1}
deb_version="${version}-1~smallgearlab${number}"
repo=google-gemini/gemini-api-cli
asset=gemini-api_Linux_x86_64.tar.gz
work=$HOME/.cache/kitty-dl/gemini-api-cli-build/$version
maintainer='small-gear-lab <289302950+marie-222@users.noreply.github.com>'

mkdir -p "$work/dl"

echo "== download $asset"
# curl, not gh: release assets are public, and gh needs a valid login only for the digest lookup below.
base=https://github.com/$repo/releases/download/v$version
curl -fsSL -o "$work/dl/$asset" "$base/$asset"
curl -fsSL -o "$work/dl/checksums.txt" "$base/checksums.txt"

actual=$(sha256sum "$work/dl/$asset" | cut -d' ' -f1)
listed=$(awk -v a="$asset" '$2==a {print $1}' "$work/dl/checksums.txt")
if [ -z "$listed" ] || [ "$listed" != "$actual" ]; then
    echo "checksums.txt mismatch: listed '$listed', got '$actual'" >&2
    exit 1
fi
echo "checksums.txt ok: $actual"

expected=$(curl -fsSL "https://api.github.com/repos/$repo/releases/tags/v$version" \
    | jq -r ".assets[] | select(.name==\"$asset\") | .digest")
if [ "$expected" != "sha256:$actual" ]; then
    echo "API digest mismatch: expected '$expected', got 'sha256:$actual'" >&2
    exit 1
fi
echo "API digest ok"

echo "== extract"
rm -rf "$work/src" "$work/root" "$work/test"
mkdir -p "$work/src" "$work/root/DEBIAN"
tar -xzf "$work/dl/$asset" -C "$work/src"
src=$work/src
root=$work/root

echo "== stage"
doc=usr/share/doc/gemini-api-cli
install -d -m 755 "$root/usr/bin" "$root/$doc"
install -m 755 "$src/gemini-api" "$root/usr/bin/gemini-api"
install -m 644 "$src/LICENSE" "$root/$doc/LICENSE"
install -m 644 "$src/README.md" "$root/$doc/README.md"

cat > "$root/$doc/copyright" <<EOF
Source: https://github.com/$repo (release v$version, $asset)

/usr/bin/gemini-api is the unmodified binary of that release. The project is licensed under
Apache-2.0; the full text shipped with the release is in LICENSE in this directory.
The Go modules linked into the binary keep their own licenses, which were not checked here.
EOF

cat > "$root/DEBIAN/control" <<EOF
Package: gemini-api-cli
Version: $deb_version
Architecture: amd64
Maintainer: $maintainer
Section: utils
Priority: optional
Homepage: https://github.com/$repo
Description: Command-line client for the Gemini API (gemini-api)
 The official gemini-api release $version: a stateless client with generate, analyze,
 transcribe and files commands, for scripts and coding agents. It can read video, audio,
 images and PDFs. Needs a GEMINI_API_KEY. Statically linked, no dependencies.
EOF

find "$root" -type d -exec chmod 755 {} +
find "$root" -type f ! -perm /111 -exec chmod 644 {} +

echo "== build"
mkdir -p "$work/out"
deb="$work/out/gemini-api-cli_${deb_version}_amd64.deb"
dpkg-deb --root-owner-group --build "$root" "$deb"

echo "== smoke test (empty environment)"
mkdir -p "$work/test/x"
dpkg-deb -x "$deb" "$work/test/x"
out=$(env -i PATH=/usr/bin:/bin "$work/test/x/usr/bin/gemini-api" --version)
echo "$out"
case "$out" in *"$version"*) ;; *) echo "version string does not contain $version" >&2; exit 1 ;; esac

echo "== done"
echo "$deb"
