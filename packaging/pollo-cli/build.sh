#!/bin/bash
# Build the pollo-cli .deb from the official Pollo AI CLI release (the npm package @pollo-ai/cli-linux-x64).
#
# Usage: build.sh [--no-clean] [version] [smallgearlab-number]
#        (--no-clean is accepted for the same interface as the other build.sh and changes nothing)
#        build.sh 0.14.0 1       ->  pollo-cli_0.14.0-1~smallgearlab1_amd64.deb
#
# Suite: resolute-testing. Upstream calls the CLI and its skills a preview ("nothing is frozen"), so it is opt-in.
#
# Why: Ubuntu has no package for the Pollo AI CLI (https://github.com/polloaiofficial/cli). Its install.sh only
# downloads the per-platform package from the npm registry and moves bin/pollo into /usr/local/bin, so this package
# does the same step as a .deb (/usr/bin/pollo). Only amd64 is built (the arm64 package is @pollo-ai/cli-linux-arm64).
# The tarball is checked twice, the same way `npm audit signatures` does: against dist.integrity (sha512) of the
# registry's metadata for that version, and against the registry's ECDSA signature of "name@version:integrity"
# (key from <registry>/-/npm/v1/keys). The binary is a statically linked Go program; it reads the CA bundle of
# the system, so ca-certificates is Recommended. There is no source: it is a repack, and the Go modules linked
# into the binary keep their own licenses, which are not enumerated here. The CLI itself is MIT (LICENSE ships
# in the package).
set -euo pipefail
for a in "$@"; do
    case "$a" in -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done
args=()
for a in "$@"; do
    if [ "$a" = --no-clean ]; then echo "--no-clean: no effect (nothing to keep)" >&2; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}

version=${1:-0.14.0}
number=${2:-1}
deb_version="${version}-1~smallgearlab${number}"
registry=https://registry.npmjs.org
pkg=@pollo-ai/cli-linux-x64
tarball=cli-linux-x64-$version.tgz
work=$HOME/.cache/kitty-dl/pollo-cli-build/$version
maintainer='small-gear-lab <289302950+marie-222@users.noreply.github.com>'

mkdir -p "$work/dl"

echo "== download $pkg@$version"
curl -fsSL -o "$work/dl/meta.json" "$registry/$pkg/$version"
curl -fsSL -o "$work/dl/keys.json" "$registry/-/npm/v1/keys"
curl -fsSL -o "$work/dl/$tarball" "$registry/$pkg/-/$tarball"

meta() { jq -r "$1" "$work/dl/meta.json"; }
[ "$(meta .name)" = "$pkg" ] && [ "$(meta .version)" = "$version" ] \
    || { echo "metadata is not for $pkg@$version" >&2; exit 1; }
integrity=$(meta .dist.integrity)
case "$integrity" in sha512-*) ;; *) echo "no sha512 integrity in the metadata: '$integrity'" >&2; exit 1 ;; esac

want=${integrity#sha512-}
got=$(openssl dgst -sha512 -binary "$work/dl/$tarball" | openssl base64 -A)
if [ "$got" != "$want" ]; then
    echo "integrity mismatch: listed '$want', got '$got'" >&2
    exit 1
fi
echo "integrity ok: sha512-${got:0:16}..."

keyid=$(meta '.dist.signatures[0].keyid')
sig=$(meta '.dist.signatures[0].sig')
key=$(jq -r --arg k "$keyid" '.keys[] | select(.keyid==$k) | .key' "$work/dl/keys.json")
if [ -z "$key" ]; then echo "the signing key $keyid is not in the registry's key list" >&2; exit 1; fi
printf '%s@%s:%s' "$pkg" "$version" "$integrity" > "$work/dl/signed-message.txt"
printf '%s' "$sig" | openssl base64 -d -A > "$work/dl/signature.bin"
printf -- '-----BEGIN PUBLIC KEY-----\n%s\n-----END PUBLIC KEY-----\n' "$key" > "$work/dl/registry-key.pem"
openssl dgst -sha256 -verify "$work/dl/registry-key.pem" -signature "$work/dl/signature.bin" \
    "$work/dl/signed-message.txt" > /dev/null \
    || { echo "registry signature does not verify (key $keyid)" >&2; exit 1; }
echo "registry signature ok ($keyid)"

echo "== extract"
rm -rf "$work/src" "$work/root" "$work/test"
mkdir -p "$work/src" "$work/root/DEBIAN"
tar -xzf "$work/dl/$tarball" -C "$work/src"
src=$work/src/package
root=$work/root
[ -f "$src/bin/pollo" ] || { echo "$pkg@$version does not contain bin/pollo" >&2; exit 1; }

echo "== stage"
doc=usr/share/doc/pollo-cli
install -d -m 755 "$root/usr/bin" "$root/$doc"
install -m 755 "$src/bin/pollo" "$root/usr/bin/pollo"
install -m 644 "$src/LICENSE" "$root/$doc/LICENSE"
install -m 644 "$src/README.md" "$root/$doc/README.md"

cat > "$root/$doc/copyright" <<EOF
Source: https://github.com/polloaiofficial/cli (npm package $pkg@$version)

/usr/bin/pollo is the unmodified binary of that npm package. The CLI is licensed under the MIT
license (Copyright (c) 2026 Pollo AI); the full text shipped with the package is in LICENSE in this
directory. The Go modules linked into the binary keep their own licenses, which were not checked here.
EOF

cat > "$root/DEBIAN/control" <<EOF
Package: pollo-cli
Version: $deb_version
Architecture: amd64
Maintainer: $maintainer
Section: utils
Priority: optional
Recommends: ca-certificates
Homepage: https://github.com/polloaiofficial/cli
Description: Command-line client for Pollo AI image and video generation (pollo)
 The official Pollo AI CLI $version: lists the models, reads each model's input fields,
 estimates the credit cost, submits a generation (local files are uploaded as part of the job)
 and waits for the result URL. "pollo mcp" runs it as a local MCP server. Log in once with
 "pollo auth login". Upstream calls it a preview. Statically linked, no dependencies.
EOF

find "$root" -type d -exec chmod 755 {} +
find "$root" -type f ! -perm /111 -exec chmod 644 {} +

echo "== build"
mkdir -p "$work/out"
deb="$work/out/pollo-cli_${deb_version}_amd64.deb"
dpkg-deb --root-owner-group --build "$root" "$deb"

echo "== smoke test (empty environment)"
mkdir -p "$work/test/x"
dpkg-deb -x "$deb" "$work/test/x"
out=$(env -i PATH=/usr/bin:/bin "$work/test/x/usr/bin/pollo" version)
echo "$out"
case "$out" in *"$version"*) ;; *) echo "version string does not contain $version" >&2; exit 1 ;; esac

echo "== done"
echo "$deb"
