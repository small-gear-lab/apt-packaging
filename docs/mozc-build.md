# Building Mozc 3.35.6354 with the UT dictionaries for Ubuntu 26.04

Ubuntu ships Mozc 2.29.5160.102 (no UT dictionaries). We rebuild Mozc 3.35.6354 from upstream, with the UT
dictionaries merged into the system dictionary, using the `debian/` directory of
<https://github.com/phoepsilonix/mozc-deb> (Bazel build with the fcitx5 patches).

Packages produced: `mozc-server`, `mozc-data`, `mozc-utils-gui`, `fcitx5-mozc`, `fcitx-mozc-data`, `ibus-mozc`,
`emacs-mozc`, `emacs-mozc-bin`. (`fcitx-mozc`, the fcitx4 engine, is not built; see below.)

Work directory: `~/.local/src/mozc/build/mozc-ut-resolute/` (`$MOZC_WORK` overrides it; Bazel's cache is keyed
on this path, so moving it makes the next build start from nothing). It holds `mozc/`, `mozc-deb/`,
`merge-ut-dictionaries/`, `.venv/` and the debs.

## Recipe

Use the script, not the steps by hand:

```
~/.local/share/apt/packaging/mozc/build.sh fetch   # the three sources at the commits in REV; venv with jaconv
~/.local/share/apt/packaging/mozc/build.sh dict    # merge the UT dictionaries, append them to dictionary00.txt
~/.local/share/apt/packaging/mozc/build.sh build   # copy debian/ in, dpkg-buildpackage -b --no-sign -nc
```

1. Sources (`REV`): `google/mozc` tag `3.35.6354` (`0136c357`), `phoepsilonix/mozc-deb` `main` (`ca112925`,
   its changelog says 3.35.6354.2), `utuhiro78/merge-ut-dictionaries` (`64084488`).
2. UT dictionaries: `merge-ut-dictionaries-make.sh.patch` turns on `alt_cannadic`, `edict2`, `neologd`,
   `skk_jisyo` (next to `jawiki`, `personal_names`, `place_names`, `sudachidict`) and sets
   `generate_latest="false"`. With `false`, `make.sh` does not process a Wikipedia dump: it clones the
   dictionaries their author publishes (`mozcdic-ut-*`, `--depth 1`), concatenates and merges them
   (`merge_dictionaries.py`, which needs `jaconv`), and the result is appended to
   `src/data/dictionary_oss/dictionary00.txt` (128,908 lines, 2,133,427 appended). This takes under a minute.
   "Latest" therefore means what the author has published, not a dump of today. The dictionaries are not
   pinned: `dicts.rev` in the work directory records the commits that were used (2026-11-01: jawiki 2026-10-02,
   personal-names and place-names 2026-10-02, sudachidict 2026-10-16, alt-cannadic 2026-09-05, edict2
   2026-07-08, neologd and skk-jisyo 2026-04-20; the last two are not updated upstream any more).
3. `debian/patches` of mozc-deb `main` (`0001-Support-fcitx.patch`, `0002-fcitx5-icon.patch`) apply to 3.35 as
   they are. The `ubuntu-resolute` branch of mozc-deb does not work for Mozc 3.x (its patches were for gyp, which
   Mozc dropped), and neither does the old `mozc-build-tweaks.patch`.
4. `debian/control` and `debian/rules` were edited: the `fcitx-mozc` package (fcitx4) with its `.install` and
   `.lintian-overrides`, `TARGET_FCITX`, the fcitx4 `.po` loop and the Build-Depends `fcitx-libs-dev` and
   `libgwengui-qt5-dev` are gone. `fcitx-libs-dev` is the fcitx4 development library: installing it **removes
   `fcitx5` and `fcitx5-mozc`**, and `libgwengui-qt5-dev` does not exist in 26.04. `fcitx-mozc-data` stays; `fcitx5-mozc` uses it.
5. Build with an empty environment (`env -i`, which `build.sh` does) and the Bazel from the Bazel apt repository.
   Bazel downloads its dependencies the first time and builds Mozc's own copies of protobuf and abseil from
   source (they are not linked dynamically; `ldd` on `mozc_server` shows neither, and the debs do not depend on
   `libprotobuf` or `libabsl`), which is why `mozc-server` is 35 MB. `~/.cache/bazel` was 3.6 GB after the first
   build. The first build took 17 minutes on 12 cores.
6. `sgl-reprepro includedeb resolute $MOZC_WORK/*_3.35.6354.2+dfsg-2.2build1.1~smallgearlab1_*.deb`.

## Build dependencies

Not `apt build-dep mozc` (see 4). What was missing on this machine and was installed by hand (42 packages with
their dependencies, nothing removed; `apt history` id 346):

```
sudo apt-get install --no-install-recommends dh-exec fcitx5-modules-dev gyp libabsl-dev \
  libfcitx5config-dev libfcitx5core-dev libfcitx5-qt6-dev libfcitx5utils-dev libgtk2.0-dev \
  libibus-1.0-dev libprotobuf-dev protobuf-compiler python3-six qt6-base-dev
```

`dpkg-checkbuilddeps packaging/mozc/debian/control` lists what is missing. **Bazel** comes from Google's apt repository
(`/etc/apt/sources.list.d/bazel.sources`: `https://storage.googleapis.com/bazel-apt stable jdk1.8`, key
`/usr/share/keyrings/bazel-archive-keyring.gpg`, fingerprint `71A1 D0EF CFEB 6281 FD04 37C9 3D59 19B4 4845 7EE0`);
the package is `bazel` (9.3.1 at the time). Ubuntu's own `bazel-bootstrap` is 4.2.3, too old. The key's old address
`bazel.build/bazel-release.pub.gpg` returns 404; the current one is `releases.bazel.build/bazel-release.pub.gpg`, and
both gave the same key.

## What the debs depend on

`mozc-server`: `libc6 (>= 2.38)`, `libstdc++6 (>= 14)`, `libgcc-s1`, `libqt6core6t64 (>= 6.9.1)`, `libqt6gui6`,
`libqt6widgets6`. `fcitx5-mozc`: `libfcitx5core7`, `libfcitx5config6`, `libfcitx5utils2` (all `>= 5.1.19`), `fcitx5`,
`mozc-server (= <same version>)`, `fcitx-mozc-data`. The Qt and fcitx5 versions are what 26.04 has; the packaging
itself has nothing specific to 26.04.

## Pitfalls we hit

| Symptom | Cause | Fix |
|---|---|---|
| `apt build-dep mozc` wants to remove `fcitx5` and `fcitx5-mozc` | the Build-Depends of Debian's `control` include `fcitx-libs-dev` (fcitx4) | edit `control` first (4), install what `dpkg-checkbuilddeps` still lists |
| `control` fails to parse after editing | a blank line left between continuation lines of `Build-Depends` | no blank lines inside the field |
| `ubuntu-resolute` branch patches 0001-0005 do not apply | Mozc 3.x has no gyp | use the `debian/patches` of `main` |
| `zsh: no such file or directory: env -i ...` | a multi-word command in a variable (`$E`) is not split by zsh | write the command out |
| a rebuild with a new `debian/changelog` version redoes everything | `dpkg-buildpackage` without `-nc` runs `bazel clean` | `build.sh` uses `-nc` and keeps `debian/.pc` |

## Updating

1. New Mozc tag: edit `REV` (`mozc`, and `mozc-deb` if its changelog moved), `build.sh fetch`, `build.sh dict`.
2. `debian/changelog`: `3.xx.yyyy.2+dfsg-2.2build1.1~smallgearlab1` (follow mozc-deb's version, then the suffix).
3. `build.sh build`, `sgl-reprepro includedeb resolute ...`, `sudo apt update`, `sudo apt upgrade`.
4. Only the dictionaries: `build.sh dict` and `build.sh build` again, with `~smallgearlab<N+1>` (Bazel's cache makes it quick).
5. When Ubuntu's archive reaches the same version or newer, the official package wins by itself (`~smallgearlab`
   sorts lower). Note that this would drop the UT dictionaries; keep an eye on it.

## Where the packaging lives

`~/.local/share/apt/packaging/mozc/`: `build.sh`, `REV`, `merge-ut-dictionaries-make.sh.patch` and `debian/` (the
source of truth: mozc-deb's `debian/` with the edits in 4 and a `~smallgearlab` entry in `changelog`).
Not kept: the work directory, the Bazel cache (`~/.cache/bazel`), the merged dictionary (about 133 MB).
