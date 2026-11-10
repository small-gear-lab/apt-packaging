#!/bin/bash
# Build the tree-sitter-cli .deb from the official tree-sitter release binary.
#
# Usage: build.sh [--no-clean] [version] [smallgearlab-number]
#        (--no-clean is accepted for the same interface as the other build.sh and changes nothing)
#        build.sh 0.27.2 1        ->  tree-sitter-cli_0.27.2-1~smallgearlab1_amd64.deb
#
# Why: nvim-treesitter (main branch) needs tree-sitter-cli >= 0.26.1 to build parsers; Ubuntu has 0.25.9.
# Same package name as Ubuntu's, so this one replaces it by version.
# The binary is tree-sitter-linux-x64.gz of https://github.com/tree-sitter/tree-sitter/releases, checked against
# the sha256 digest GitHub reports for the asset. The license comes from the source at the same tag (the
# tarball's embedded commit id must equal the commit the tag points to). It is a repack: the Rust crates linked
# into the binary keep their own licenses, which are not enumerated here.
set -euo pipefail
for a in "$@"; do
    case "$a" in -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done
args=()
for a in "$@"; do
    if [ "$a" = --no-clean ]; then echo "--no-clean: no effect (nothing to keep)" >&2; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}

version=${1:-0.27.2}
number=${2:-1}
deb_version="${version}-1~smallgearlab${number}"
asset=tree-sitter-linux-x64.gz
tag=v$version
work=$HOME/.cache/nvim-dl/tscli/build-$version
maintainer='small-gear-lab <289302950+marie-222@users.noreply.github.com>'
curl() { env -u LD_LIBRARY_PATH /usr/bin/curl -fsSL "$@"; }

rm -rf "$work"
mkdir -p "$work/dl" "$work/src" "$work/root/DEBIAN" "$work/out"

echo "== download $asset"
gh release download "$tag" -R tree-sitter/tree-sitter -p "$asset" -D "$work/dl" --clobber
expected=$(gh api "repos/tree-sitter/tree-sitter/releases/tags/$tag" --jq ".assets[] | select(.name==\"$asset\") | .digest")
actual=sha256:$(sha256sum "$work/dl/$asset" | cut -d' ' -f1)
if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "digest mismatch: expected '$expected', got '$actual'" >&2
    exit 1
fi
echo "digest ok: $actual"
gzip -dc "$work/dl/$asset" > "$work/tree-sitter"

echo "== source at the tag (license)"
curl -o "$work/dl/src.tar.gz" "https://github.com/tree-sitter/tree-sitter/archive/refs/tags/$tag.tar.gz"
# get-tar-commit-id stops reading after the header, so gzip gets SIGPIPE: not an error here.
embedded=$(set +o pipefail; gzip -dc "$work/dl/src.tar.gz" | git get-tar-commit-id)
ref=$(gh api "repos/tree-sitter/tree-sitter/git/ref/tags/$tag" --jq '.object.type + " " + .object.sha')
if [ "${ref%% *}" = tag ]; then
    tagged=$(gh api "repos/tree-sitter/tree-sitter/git/tags/${ref#* }" --jq .object.sha)
else
    tagged=${ref#* }
fi
[ "$embedded" = "$tagged" ] || { echo "source tarball commit $embedded != tag commit $tagged" >&2; exit 1; }
echo "source ok: $tag = $tagged"
tar -xzf "$work/dl/src.tar.gz" -C "$work/src" --strip-components=1

root=$work/root
echo "== stage"
install -d -m 755 "$root/usr/bin" "$root/usr/share/doc/tree-sitter-cli"
install -m 755 "$work/tree-sitter" "$root/usr/bin/tree-sitter"
install -m 644 "$work/src/LICENSE" "$root/usr/share/doc/tree-sitter-cli/LICENSE"
gzip -9n -c > "$root/usr/share/doc/tree-sitter-cli/changelog.Debian.gz" <<EOF
tree-sitter-cli ($deb_version) resolute; urgency=medium

  * Repack of the official $asset of tree-sitter $version.

 -- $maintainer  $(date -R)
EOF

cat > "$root/usr/share/doc/tree-sitter-cli/copyright" <<EOF
Source: https://github.com/tree-sitter/tree-sitter (release $tag, $asset)

Files: *
Copyright: Max Brunsfeld and the tree-sitter contributors
License: MIT
 The full text is in /usr/share/doc/tree-sitter-cli/LICENSE.

The binary is the unmodified official release build. It is statically linked and contains Rust crates
under their own licenses; those licenses are not enumerated in this package.
EOF

cat > "$root/DEBIAN/control" <<EOF
Package: tree-sitter-cli
Version: $deb_version
Architecture: amd64
Maintainer: $maintainer
Section: devel
Priority: optional
Homepage: https://tree-sitter.github.io/
Depends: libc6 (>= 2.39), libgcc-s1 (>= 4.2)
Description: command-line for Tree-sitter parsers
 The tree-sitter command-line tool: generates and builds parsers from grammars
 (used e.g. by nvim-treesitter). A repack of the official release binary.
EOF

find "$root" -type d -exec chmod 755 {} +
find "$root" -type f ! -perm /111 -exec chmod 644 {} +

echo "== build"
deb="$work/out/tree-sitter-cli_${deb_version}_amd64.deb"
dpkg-deb --root-owner-group --build "$root" "$deb"
echo "== smoke test"
env -i PATH=/usr/bin:/bin "$root/usr/bin/tree-sitter" --version
echo "== done"
echo "$deb"
