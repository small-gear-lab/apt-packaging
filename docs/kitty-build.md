# Building kitty 0.49.2 for Ubuntu 26.04

Ubuntu ships 0.45.0 (plus ESM security updates). We rebuild upstream 0.49.2 from the
Ubuntu source package's `debian/` directory.

Working tree: `~/.cache/kitty-dl/deb/build/kitty-0.49.2/`
Downloads: `~/.cache/kitty-dl/v0.49.2/` (source, prebuilt archive, signatures)

Packages produced: `kitty`, `kitty-doc`, `kitty-terminfo`, `kitty-shell-integration`.

## Recipe

1. Source: `apt source kitty` (deb-src is enabled) for `debian/`; the upstream
   `kitty-0.49.2.tar.xz` from the GitHub release for the code. Signatures are made
   by Kovid Goyal's key, <https://calibre-ebook.com/signatures/kovid.gpg>.
2. Copy `debian/` into the upstream tree. Debian patches that no longer apply were dropped
   (tests, a docs image, "ignore vendor dir", "remove toolchain"); "toolchain" was re-done as
   `0015-remove-toolchain-directive.patch`. The gopsutil v4 path patch was dropped too,
   because it rewrites imports for Debian's `-dev` packages only.
3. Go dependencies: 0.49.2 needs modules that Ubuntu does not package (`kovidgoyal/*`,
   `emmansun/base64`, `hako/durafmt`, `sgtdi/fswatcher`), so `go mod vendor` is run in the
   tree (`GOFLAGS=-mod=mod GOTOOLCHAIN=local go mod vendor`).
4. `debian/rules` was rewritten from GOPATH mode to modules: `GOFLAGS=-mod=vendor`,
   `GOTOOLCHAIN=local`, `python3 setup.py linux-package`, `KITTEN_EXE_FOR_DOCS` set to
   `linux-package/bin/kitten`; tests are skipped.
5. `debian/control`: all `golang-*-dev` Build-Depends removed, `kitty-slang-compiler (>= 2026.14.1)`
   (our own package, see below) and `python3-sphinx-design` added. `kitty` Depends on `libfontconfig1` and `libsystemd0`
   (both loaded with dlopen, so dpkg-shlibdeps cannot see them); Suggests `slang-compiler`.
6. Build, then `sgl-reprepro includedeb resolute *.deb`.

Build dependencies to install by hand: `libsimde-dev kitty-slang-compiler python3-sphinx-design`
(`kitty-slang-compiler` comes from this repo).

## Build command

```
cd ~/.cache/kitty-dl/deb/build/kitty-0.49.2
env -i HOME="$HOME" LOGNAME="$USER" USER="$USER" LANG=C.UTF-8 TERM="$TERM" \
    PATH=/usr/sbin:/usr/bin:/sbin:/bin \
    PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig \
    DEB_BUILD_OPTIONS=nocheck \
    dpkg-buildpackage -us -uc -b -nc
```

`SLANGC` is set inside `debian/rules` (`/usr/lib/kitty-slang-compiler/bin/slangc`), so it must not
be passed from outside any more. The `-d` flag is no longer needed because the build
dependencies are satisfiable.

`-nc` is needed: the clean step wiped `vendor/`. When rebuilding, remove `build/`,
`linux-package/`, `debian/.debhelper`, `debian/tmp`, `debian/debhelper-build-stamp` and the
per-package output directories first, otherwise debhelper skips the build step.

Build in an **empty environment** (`env -i`, which `build.sh` does since `~smallgearlab6`). The login
shell exports `LD_RUN_PATH=/usr/local/lib`, and ld turns that into `RUNPATH /usr/local/lib` in every
ELF it links (lintian: custom-library-search-path). `~smallgearlab5` and older have it in `/usr/bin/kitty`
and the `.so` files. Unsetting variables one by one misses the next one.

A rebuild is not bit-identical: man pages carry the build date, `shaders/*.json` list entry points in a
different order, and the machine code is the same except for relative offsets. To compare with the installed
package, normalise `objdump -d` (addresses, immediates) instead of hashing `.text`.

## Pitfalls we hit

| Symptom | Cause | Fix |
|---|---|---|
| `FileNotFoundError: /usr/local/bin/wayland-scanner` | stale `.pc` files of an old Wayland install in `/usr/local/lib/x86_64-linux-gnu/pkgconfig` (2025-06) point at a binary that is gone | `PKG_CONFIG_LIBDIR` limited to the system directories (do not touch `/usr/local`) |
| build used Python 3.15 | the `python3` shim of pyenv came first in `PATH` | `PATH=/usr/sbin:/usr/bin:/sbin:/bin` |
| `go list -m` failed: inconsistent vendoring | `vendor/` was removed or stale | rerun `go mod vendor`; build with `-nc` |
| docs: `No module named 'sphinx_design'` | new docs dependency in 0.49 | `python3-sphinx-design` |
| docs: kitten binary not found | docs look at `kitty/launcher/kitten` | `KITTEN_EXE_FOR_DOCS` in `debian/rules` |
| **new windows never open**: `Failed to compile GLSL vertex shader ... GL_ARB_shading_language_420pack` | 0.49.2 needs slang 2026.14.1 (`bypy/sources.json`); Ubuntu's `slang-compiler` is 2026.1.1 and emits GLSL that Mesa rejects | build with the slangc of the official 2026.14.1 release, packaged as `kitty-slang-compiler` (its `slangc` finds its libraries through `$ORIGIN/../lib`; never set `LD_LIBRARY_PATH` for the whole build, the bundled old libexpat breaks the launcher link) |

## kitty-slang-compiler

Our own binary package: `slangc` and the libraries it loads (`libslang-compiler`,
`libslang-glsl-module`, `libslang-glslang`, the standard module directory) taken unchanged from the
**official Slang release** (`slang-<version>-linux-x86_64-glibc-2.27.tar.gz` on
<https://github.com/shader-slang/slang/releases>) and installed only under
`/usr/lib/kitty-slang-compiler/` (nothing on `PATH`, so Ubuntu's `slang-compiler` is not
affected). It depends on `libc6`, `libstdc++6` and `libgcc-s1`.

Build it with the script, not by hand:

```
~/.local/share/apt/packaging/kitty-slang-compiler/build.sh <slang version> <smallgearlab number>
# e.g. build.sh 2026.14.1 2  ->  kitty-slang-compiler_2026.14.1-1~smallgearlab2_amd64.deb
```

The script downloads the archive, compares its sha256 with the `digest` GitHub reports for the
asset (it stops on a mismatch), stages the files, installs `LICENSE`, `LICENSES/` and a
`copyright` file under `/usr/share/doc/kitty-slang-compiler/`, builds the deb with `dpkg-deb`
(directories 755, files 644) and compiles a small `.slang` vertex shader with `env -i` as a
smoke test. Output: `~/.cache/kitty-dl/slang-build/<version>/out/`.

- The version is visible in the library file names (`libslang-compiler.so.0.2026.14.1`) and
  `slangc -version` prints it, so no trust in third-party notes is needed. (The copy inside the
  kitty archive only printed a build timestamp, which is why it was replaced.)
- Which version: the one in `bypy/sources.json` of the kitty source. A newer slang (2026.20 exists)
  may change the GLSL that kitty post-processes, so do not move ahead of kitty's pin without a test.
- License check (2026-10-28): the release is `Apache-2.0 WITH LLVM-exception`; `LICENSES/` holds
  Apache-2.0, LLVM-exception, MIT, BSL-1.0, Unlicense, CC-BY-4.0 and `LicenseRef-UOI-NCSA`, all
  permissive. kitty is GPL-3.0 but only runs slangc at build time and ships none of it. Not checked:
  whether every bundled third-party component (glslang, SPIRV-Tools, ...) is covered by `LICENSES/`.
- Switching kitty from the older copy to the official release changed only `shaders/*.json`
  (entry point order) and `shaders/slangc.version` (`1790821642` -> `2026.14.1`); the GLSL is identical.
- If Ubuntu gets slang 2026.14.1 or newer, drop this package and depend on `slang-compiler` again.

Custom user shaders use whichever `slangc` is on `PATH` (the Suggested `slang-compiler`), which
may be too old for kitty 0.49.

## Updating to a new upstream version

1. Download the new source and prebuilt archive, verify the signatures.
2. Update `go.mod`-derived vendor, check `bypy/sources.json` for the slang version.
3. `dch --newversion <upstream>-1~smallgearlab1` and rebuild.
4. `sgl-reprepro includedeb resolute *.deb`, `sudo apt update`, `sudo apt upgrade`.
5. When Ubuntu's archive reaches the same upstream version, nothing needs to be done:
   `~smallgearlab` sorts lower and the official package wins.

## Where the packaging lives

`~/.local/share/apt/packaging/kitty/debian/` is the source of truth for the kitty packaging
(`changelog`, `control`, `rules`, `patches/`, `external/fonts` ...). The work tree under
`~/.cache/kitty-dl/deb/build/` is disposable: it can be recreated with steps 1-4 above and
`build.sh build`.

```
~/.local/share/apt/packaging/kitty/build.sh save  [version]   # work tree -> packaging (after editing there)
~/.local/share/apt/packaging/kitty/build.sh build [version]   # packaging -> work tree, clean state, build
```

`build` assumes the quilt patches in the work tree match `debian/patches` (the normal rebuild case).
To change a patch: edit it in the work tree with quilt (`QUILT_PATCHES=debian/patches`), run `save`,
then `build`. The packaging is not under git yet.

## Local patches (debian/patches)

| Patch | What and why |
|---|---|
| `0015-remove-toolchain-directive.patch` | drops the `toolchain` line of `go.mod` (the Debian patch for it no longer applied) |
| `0016-ime-preedit-straight-underline-no-italic.patch` | 0.49 draws IME pre-edit text italic with a dashed underline (hard-coded in `screen_draw_overlay_line`, no option). Now: straight underline, no italic |
| `0017-ime-preedit-mark-cursor-cell.patch` | draws the one code point at the IME cursor in reverse video during conversion |

Notes on 0017:

- Under Wayland text-input-v3 the input method sends `cursor_begin` and `cursor_end`. With fcitx5 + Mozc
  both are always equal (checked with `kitty --debug-input`): while typing kana the cursor is at the end of
  the text, during conversion it is the start of the selected clause (0, 6, ...). The end of the clause is
  not sent, so only the first character of the clause can be marked, not the whole clause.
- kitty dropped this value, and also dropped events where only the cursor moved (`text_input_done` skipped
  unchanged text). The patch passes it through `GLFWkeyevent` (`ime_cursor_valid`, `ime_cursor_begin`),
  `screen_update_overlay_text(..., cursor_byte_offset)` and `OverlayLine.mark_pos`. The byte offset is
  converted to a code point index; offsets at or after the end of the text mark nothing.
- `kitty/glfw-wrapper.h` is a generated copy of the struct in `glfw/glfw3.h`; both are patched by hand and
  must stay identical.
- Checked: it builds and starts without errors. Not checked by me: how it looks while converting (needs a
  real IME session).
- Files touched: `glfw/glfw3.h`, `glfw/wl_text_input.c`, `kitty/glfw-wrapper.h`, `kitty/keys.c`,
  `kitty/screen.c`, `kitty/screen.h`. Re-check them on every kitty update.
- Blinking text exists in 0.49 (`sgr.blink`), so a blinking mark would also be possible.

## kitty.conf changes that came with 0.49 (user side, not in the package)

- `symbol_map ... Symbols Nerd Font Mono` (the line from the kitty FAQ, Nerd Fonts v3.4.0): without it
  U+F07C (the folder icon of the powerlevel10k prompt) was drawn by UnDotum, a Korean font that has a
  different glyph at that private-use code point. kitty only falls back to its builtin Nerd Font for symbols
  that no installed font has. Why 0.45 did not show it is unknown; not checked whether the upstream prebuilt
  0.49.2 behaves the same.
- `active_tab_font_style bold` (default `bold-italic`).
- The `hints_*_color` lines were never valid kitty.conf options; the colors are now arguments of the
  `kitten hints` map (`--hints-foreground-color` etc.).
- Backups: `~/.config/kitty/kitty.conf.bak-2026-10-28`, `-b`, `-c`.

## The Symbols Nerd Font follows kitty

Ubuntu's source package kept a copy of `SymbolsNerdFontMono-Regular.ttf` in `debian/external/fonts/`
(Nerd Fonts v3.2.1). Here the font is not stored: `build.sh build` (or `build.sh fetch-font`) takes it out of
kitty's own binary release archive, `kitty-<version>-x86_64.txz`, after checking its signature against Kovid
Goyal's key. So the font is whatever Nerd Fonts version upstream kitty ships for that release (v3.3.0 for kitty
0.49.2), and a new kitty version brings its own font without anything to update here. Nothing of it stays in
`debian/external/fonts/`.

The license documents follow the font the same way. The font in kitty's archive carries no version, so `build.sh`
looks for the Nerd Fonts release whose `NerdFontsSymbolsOnly.tar.xz` holds the identical file (newest first, the
latest 30 releases) and fetches that release's `LICENSE` (the asset's, MIT), the repository's `LICENSE` (it has
the SIL OFL 1.1 text) and `license-audit.md` (the licenses of the glyph sets the font gathers). They are
installed with the font into `/usr/lib/kitty/fonts/`, together with `NERD-FONTS-VERSION` (which release it is).

The glyph sets are not all MIT: CC-BY-4.0 (Codicons, Font Awesome), Apache-2.0 (Material Design Icons), OFL-1.1
(Pomicons, Weather Icons) and others. `debian/copyright` carries a summary for the release that was checked
(v3.3.0). When kitty moves to another Nerd Fonts release, read the new `license-audit.md` and update that
summary. The audit tables of v3.3.0 and v3.5.1 differ only in the list of other fonts, not in the Symbols Only
row or the glyph-set table, and the repository `LICENSE` is identical.

Why not read a version from the source: the source tarball has no pin, and kitty's `bypy/devenv.go` fetches
the `latest` Nerd Fonts release, so the release archive is the only place that records what upstream chose.
If no release among the latest 30 holds the font, `build.sh` stops and says so: find the release by hand and
read its `LICENSE` and `license-audit.md` before shipping the font.

## The Go modules linked into kitten

`kitten` (and the other Go programs) is linked statically with the modules that `go mod vendor` put in `vendor/`
(36 for 0.49.2) and with the Go standard library, so the package has to carry their licenses and copyright
notices. Ubuntu's `debian/copyright` listed only the handful of modules it had vendored for 0.45.0.

`build.sh build` runs `gen-vendor-licenses.py` on the work tree: for every module in `vendor/modules.txt` it
copies the module's license files (`LICENSE`, `COPYING`, `NOTICE`, `PATENTS`; from a parent directory when the
module is a sub-module of a monorepo) into `debian/vendor-licenses/<module>/`, which `debian/kitty.docs` installs
as `/usr/share/doc/kitty/vendor-licenses/`, and writes `debian/copyright` as the base copyright (this directory's
`debian/copyright`) plus one paragraph per module. The license is told from the text of the license file; one file
may hold several (`klauspost/compress` is Apache-2.0 and BSD-3-Clause and Expat). The Go standard library takes the
`License: Go` paragraph of Debian's `golang-<version>-go` copyright file (BSD-3-Clause plus Google's patent grant).

If a module's license is not recognised, or it has no license file, the build stops and names it. Look at its
license, then add `module<TAB>license` to `vendor-license-overrides.tsv` (Debian short names, `Expat` is MIT).
`vendor-holders.tsv` adds copyright holders that the source files name but the license file does not.

The generated `debian/copyright` in the work tree is never saved back: `build.sh save` skips it. Edit the base.
Not covered: the C code under `3rdparty/` and `glfw/` is described by the base copyright as before.
