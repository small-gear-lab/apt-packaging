#!/bin/bash
# Build the Mozc debs with the UT dictionaries merged in (mozc-server, mozc-data, mozc-utils-gui, fcitx5-mozc,
# fcitx-mozc-data, ibus-mozc, emacs-mozc, emacs-mozc-bin) from phoepsilonix/mozc-deb's debian/ and google/mozc.
#
#   build.sh fetch   get the three sources at the commits named in REV (shallow clones), and a Python venv with
#                    jaconv (the dictionary merge needs it; it stays inside the work directory)
#   build.sh dict    merge the UT dictionaries (utuhiro78/merge-ut-dictionaries, make.sh with
#                    merge-ut-dictionaries-make.sh.patch) and append them to mozc's dictionary00.txt, which is
#                    reset first, so this can be repeated. The dictionaries are the ones their author publishes
#                    (generate_latest="false"): nothing is built from a Wikipedia dump. They are not pinned;
#                    the commits that were used are written to dicts.rev in the work directory
#   build.sh build [--no-clean]
#                    copy debian/ from this directory into the tree and build the debs (the build needs the
#                    network the first time: Bazel fetches its dependencies). --no-clean is accepted for the
#                    same interface as the other build.sh and changes nothing: this build never cleans
#
# debian/ in this directory is the source of truth (edit it here, then `build`). The work directory is not thrown away between builds on
# purpose: Bazel's cache is keyed on its path, and `bazel clean` (what debian/rules runs as the clean step) would
# discard it, so `build` uses -nc. Delete the directory to start from nothing.
# Layout: $MOZC_WORK (default ~/.local/src/mozc/build/mozc-ut-resolute)/{mozc,mozc-deb,merge-ut-dictionaries,.venv}.
# The debs end up in $MOZC_WORK/. Add them with
#   sgl-reprepro includedeb resolute $MOZC_WORK/*_<version>_*.deb
# (Not `apt build-dep mozc`: it pulls in fcitx-libs-dev, which removes fcitx5 and fcitx5-mozc.)
set -euo pipefail
# -h/--help: the comment at the top of this file, before anything else is read or done.
for a in "$@"; do
    case "$a" in -h|--help) sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
done

here=$(cd "$(dirname "$0")" && pwd)
# --no-clean (build only): accepted so that every build.sh takes it, and a no-op here, because the work directory is
# always kept and the build always runs with -nc (see above).
args=()
for a in "$@"; do
    if [ "$a" = --no-clean ]; then echo "--no-clean: no effect, mozc never cleans" >&2; else args+=("$a"); fi
done
set -- ${args[@]+"${args[@]}"}
cmd=${1:-}
work=${MOZC_WORK:-$HOME/.local/src/mozc/build/mozc-ut-resolute}
tree=$work/mozc

rev() { awk -v n="$1" '$1 == n { print $2 }' "$here/REV"; }

# shallow clone of one commit (a tag is fine too: it names the same commit)
fetch_rev() {
    local dir=$1 url=$2 sha=$3
    if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD)" = "$sha" ]; then
        echo "$dir: already at ${sha:0:12}"
        return
    fi
    rm -rf "$dir"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch -q --depth 1 origin "$sha"
    git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
    echo "$dir: ${sha:0:12}"
}

# An empty environment: the login shell's LD_RUN_PATH, PKG_CONFIG_PATH and friends must not leak into the build
# (see curl-build.md). bazel is the one from apt (/usr/bin/bazel, the Bazel apt repository).
build_env() {
    env -i HOME="$HOME" LOGNAME="${LOGNAME:-$USER}" USER="${USER:-$LOGNAME}" LANG=C.UTF-8 TERM="${TERM:-dumb}" \
        PATH=/usr/sbin:/usr/bin:/sbin:/bin \
        PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
        "$@"
}

do_fetch() {
    mkdir -p "$work"
    fetch_rev "$work/mozc" https://github.com/google/mozc "$(rev mozc)"
    fetch_rev "$work/mozc-deb" https://github.com/phoepsilonix/mozc-deb "$(rev mozc-deb)"
    fetch_rev "$work/merge-ut-dictionaries" https://github.com/utuhiro78/merge-ut-dictionaries "$(rev merge-ut-dictionaries)"
    if [ ! -x "$work/.venv/bin/python" ]; then
        /usr/bin/python3 -m venv "$work/.venv"
        "$work/.venv/bin/pip" install -q jaconv
    fi
}

do_dict() {
    local merge=$work/merge-ut-dictionaries/src/merge
    local dic=$work/mozc/src/data/dictionary_oss/dictionary00.txt
    git -C "$work/merge-ut-dictionaries" checkout -q -- src/merge/make.sh
    git -C "$work/merge-ut-dictionaries" apply "$here/merge-ut-dictionaries-make.sh.patch"
    (cd "$merge" && PATH="$work/.venv/bin:$PATH" sh make.sh)
    git -C "$work/mozc" checkout -q -- src/data/dictionary_oss/dictionary00.txt
    cat "$merge/mozcdic-ut.txt" >> "$dic"
    for r in "$merge"/mozcdic-ut-*/; do
        echo "$(basename "$r") $(git -C "$r" rev-parse HEAD) $(git -C "$r" log -1 --format=%ad --date=short)"
    done > "$work/dicts.rev"
    echo "merged: $(wc -l < "$merge/mozcdic-ut.txt") lines; dictionary00.txt now has $(wc -l < "$dic") lines"
    cat "$work/dicts.rev"
}

do_build() {
    local pc=$work/.pc.keep
    # The patches in debian/patches are already applied to the tree after the first build; dpkg-source keeps
    # that in debian/.pc, so keep it across the copy.
    rm -rf "$pc"
    [ -d "$tree/debian/.pc" ] && mv "$tree/debian/.pc" "$pc"
    rm -rf "$tree/debian"
    cp -a "$here/debian" "$tree/debian"
    [ -d "$pc" ] && mv "$pc" "$tree/debian/.pc"
    cd "$tree"
    build_env dpkg-buildpackage -b --no-sign -nc
    echo "debs: $(ls "$work"/*.deb | wc -l) in $work"
}

case "$cmd" in
fetch) do_fetch ;;
dict) do_dict ;;
build) do_build ;;
*)
    sed -n '2,/^set -e/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
