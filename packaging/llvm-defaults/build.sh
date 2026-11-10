#!/bin/bash
# Build the unversioned LLVM meta packages (clang, llvm, lld, lldb, ...) so that they follow LLVM <N>.
#
# Usage: build.sh [--no-clean] [llvm-major] [smallgearlab-number]
#        build.sh 24 1        ->  clang_24.0-0~smallgearlab1_amd64.deb, llvm_..., lld_..., ...
#
# Why these packages exist: the unversioned names (clang, llvm, lld, lldb, clang-format,
# llvm-dev, llvm-runtime, libclang-dev) come from apt.llvm.org's llvm-defaults meta package,
# which still points at 23 although clang-24 is already there. These replacements have the same
# names, depend on the -<N> packages and carry the same /usr/bin etc. symlinks, so `clang`
# becomes clang-<N> without update-alternatives.
#
# links.tsv is the manifest: "package<TAB>path<TAB>target", the target with the major written as
# -@V@. It was taken from the official 23 packages (dpkg -L plus readlink). Redo it when a tool
# is added or removed upstream (llvm-sim is already gone in 24, so it was dropped). Output goes to ~/.cache/llvm-defaults-build/.
set -euo pipefail
# -h/--help: the comment at the top of this file, before anything else is read or done.
for a in "$@"; do
    case "$a" in -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done
# --no-clean: accepted so that every build.sh takes it, and a no-op here: the work tree is made again every time.
args=()
for a in "$@"; do
    if [ "$a" = --no-clean ]; then echo "--no-clean: no effect (nothing to keep)" >&2; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}

here=$(cd "$(dirname "$0")" && pwd)
major=${1:-24}
number=${2:-1}
# Epoch 1 like the official packages. Revision 0: "-0~smallgearlab" is below any official 1:<N>.0-<rev>, so
# the official meta takes over once it reaches <N>; above the current official 1:23.0-71 (the major decides).
version="1:${major}.0-0~smallgearlab${number}"
work=$HOME/.cache/llvm-defaults-build
maintainer='small-gear-lab <289302950+marie-222@users.noreply.github.com>'

# package -> Section, Depends. llvm and llvm-dev need llvm-runtime at exactly the same version.
declare -A section depends summary
section=([clang]=devel [clang-format]=devel [libclang-dev]=libdevel [llvm]=devel [llvm-dev]=devel [llvm-runtime]=devel [lld]=devel [lldb]=devel)
depends=(
    [clang]="clang-$major (>= 1:$major~)"
    [clang-format]="clang-format-$major (>= 1:$major~)"
    [libclang-dev]="libclang-$major-dev (>= 1:$major~)"
    [llvm]="llvm-runtime (= $version), llvm-$major (>= 1:$major~)"
    [llvm-dev]="llvm-runtime (= $version), llvm-$major-dev (>= 1:$major~), llvm"
    [llvm-runtime]="llvm-$major-runtime (>= 1:$major~)"
    [lld]="lld-$major (>= 1:$major~)"
    [lldb]="lldb-$major (>= 1:$major~)"
)
summary=(
    [clang]="C, C++ and Objective-C compiler (LLVM based), clang binary"
    [clang-format]="Tool to format C/C++/Obj-C code"
    [libclang-dev]="clang library - Development package"
    [llvm]="Modular compiler and toolchain technologies"
    [llvm-dev]="Modular compiler and toolchain technologies, libraries and headers"
    [llvm-runtime]="Modular compiler and toolchain technologies, IR interpreter"
    [lld]="LLVM-based linker"
    [lldb]="Next generation, high-performance debugger"
)

rm -rf "$work"
mkdir -p "$work/out"
for pkg in clang clang-format libclang-dev llvm llvm-dev llvm-runtime lld lldb; do
    root=$work/root/$pkg
    mkdir -p "$root/DEBIAN" "$root/usr/share/doc/$pkg"

    n=0
    while IFS=$'\t' read -r p path target; do
        [ "$p" = "$pkg" ] || continue
        mkdir -p "$root$(dirname "$path")"
        ln -s "${target//@V@/$major}" "$root$path"
        n=$((n + 1))
    done < "$here/links.tsv"

    cat > "$root/usr/share/doc/$pkg/copyright" <<COPY
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $pkg
Source: https://github.com/small-gear-lab/apt-packaging

Files: *
Copyright: 2026 Small Gear Lab
License: MIT or Apache-2.0
 This package holds only symbolic links to the versioned LLVM $major packages
 (and their package metadata). On Debian systems the text of the Apache License 2.0
 is in /usr/share/common-licenses/Apache-2.0.
COPY

    cat > "$work/changelog" <<LOG
$pkg ($version) resolute; urgency=medium

  * Unversioned $pkg follows LLVM $major instead of the apt.llvm.org default.

 -- $maintainer  $(date -R)
LOG
    gzip -9n -c "$work/changelog" > "$root/usr/share/doc/$pkg/changelog.Debian.gz"

    size=$(du -sk "$root/usr" | cut -f1)
    cat > "$root/DEBIAN/control" <<CTRL
Package: $pkg
Version: $version
Section: ${section[$pkg]}
Priority: optional
Architecture: amd64
Installed-Size: $size
Maintainer: $maintainer
Depends: ${depends[$pkg]}
Description: ${summary[$pkg]}
 Unversioned name for LLVM $major: depends on the -$major packages and links the
 unversioned commands to them ($n links). Replaces the apt.llvm.org package of the same
 name, which is still on LLVM 23.
CTRL

    find "$root" -type d -exec chmod 755 {} +
    find "$root/usr/share/doc" -type f -exec chmod 644 {} +
    dpkg-deb --root-owner-group --build "$root" "$work/out/${pkg}_${version#1:}_amd64.deb" >/dev/null
    echo "built $pkg ($n links)"
done
rm -f "$work/changelog"
ls -l "$work/out"
