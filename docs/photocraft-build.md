# storytold-photocraft: the PhotoCraft editor and its CLI

PhotoCraft (https://github.com/storytold/photocraft) is an open-source image editor written in Rust. The source package
`storytold-photocraft` makes two binary packages, in `resolute-testing`:

| Package | What |
|---|---|
| `storytold-photocraft` | `/usr/bin/photocraft`, the editor window (desktop entry, MIME types, icons, man page) |
| `storytold-photocraft-cli` | `/usr/bin/photocraft-cli`: headless converter, command runner and MCP server (man pages, shell completions). No windowing or GPU dependencies |

The editor `Recommends` the CLI and `storytold-craft-fonts` (a metapackage for the font families upstream builds and
tests with); the CLI only `Suggests` the editor. Both programs link the same engine crates statically, so nothing is
shared between the two packages except the licence documents, which are installed in both.

## Building

Built from the upstream tag with the builder's own rustup toolchain (not Ubuntu's rustc and cargo), offline, from the
crates that `build.sh fetch` vendored:

```
packaging/storytold-photocraft/build.sh fetch 0.23.1     # tag tarball, commit check, cargo vendor (needs the network)
packaging/storytold-photocraft/build.sh build 0.23.1 2>&1 | tee ~/.cache/photocraft-dl/log/build-0.23.1.txt
sgl-reprepro includedeb resolute-testing ~/.cache/photocraft-dl/deb/build/*_0.23.1-1~smallgearlab1_amd64.deb
```

- `fetch` ties GitHub's (unsigned) tag tarball to the tag: the commit recorded in the tarball must equal the commit the
  tag points to. The sha256 of the tarball is remembered in `SHA256SUMS` on first use and checked afterwards.
- `build` stops if the local rustc is older than the strictest `rust-version` among the crates that are linked in.
- A build takes a while (about 900 crates, two cargo runs: one for the programs, one for the example that writes the
  CLI's man pages and completions, which is kept apart so that its dev-dependencies' features do not leak into the
  binaries) and the machine is busy meanwhile.
- Upstream's `[patch.crates-io]` names crates that nothing uses; `build.sh` drops those from `Cargo.toml` and
  `Cargo.lock` together (`drop_unused_patches`), because offline cargo cannot find them in `vendor/`.
- `gen-crate-licenses.py` accounts for the licence of every crate that is linked in and stops the build for one it
  cannot settle, so that a new upstream version cannot slip a licence past unseen.

## Moving to a new upstream version

Four places name the version, and `fetch` and `build` are given it on the command line:

1. `build.sh`: the default `version=${2:-...}`
2. `debian/changelog`: a new entry `<version>-1~smallgearlab1`
3. `debian/photocraft.1`: the version in the `.TH` line
4. `SHA256SUMS`: `fetch` appends the new line

Then fetch, build and include as above. If the new tag changed the bundled third-party material (fonts, icons,
dictionaries), compare upstream's `NOTICE` and `ATTRIBUTION.md` with `debian/copyright` and `debian/*.docs`.

Upstream releases often (0.20.1 to 0.23.1 took about a week), and the GitHub release notes are lists of pull requests;
`gh release list -R storytold/photocraft` shows what is new.

## storytold-vectorcraft: the same recipe for VectorCraft

VectorCraft (https://github.com/storytold/vectorcraft, a vector illustration editor from the same organisation) is
packaged in `packaging/storytold-vectorcraft/` as a copy of this one, with the same two packages
(`storytold-vectorcraft`, `storytold-vectorcraft-cli`), the same `build.sh fetch` / `build` and the same four places to
change for a new version (`photocraft.1` is `vectorcraft.1` there). It builds in `~/.cache/vectorcraft-dl/`. What differs
from PhotoCraft:

- The CLI has no example that writes man pages and shell completions, so `debian/vectorcraft-cli.1` is written by
  hand and there are no completions. Check it against `vectorcraft-cli --help` after an upgrade.
- HEIC/HEIF is a default feature of `vectorcraft-engine`, so the build passes no `--features heif`.
- The bundled third-party material is another set: Source Sans 3, Source Serif 4, Inter and JetBrains Mono (the
  CLI needs the first three), Lucide icons, Indic hyphenation patterns and the PDF backend's data (Foxit fonts,
  Adobe CMaps, a CGATS ICC profile; `licenses/pdf-backend/`). `debian/copyright` and the `.docs` files list them.
- `gen-crate-licenses.py` is the same script in both directories (only the names differ). VectorCraft's build was the
  first to need two things that it now has in both: it reads the old `A / B` choice in a crate's license field
  (`fnv`), and it takes the Ubuntu Font Licence from `fonts/UFL.txt` of `epaint_default_fonts`. Run on PhotoCraft's
  0.23.1 tree, the changed script writes the same `debian/copyright` and `vendor-licenses/` as before.

The editor window and `vectorcraft-cli` were checked by converting an SVG to PDF with the packaged CLI; the editor
window itself was not started.

## storytold-filmcraft and storytold-effectcraft: the same recipe again

FilmCraft (video editor, 0.20.1) and EffectCraft (motion graphics, 0.25.1) are packaged in `packaging/storytold-filmcraft/` and
`packaging/storytold-effectcraft/`, copies of the VectorCraft directory with the same two packages each (`-cli` carries
`/usr/bin/<app>-cli`), the same `build.sh fetch` / `build`, and builds in `~/.cache/<app>-dl/`. What differs:

- Both depend on ALSA (`libasound2t64 | libasound2`, loaded at run time) and Build-Depend on `libasound2-dev`.
- The bundled fonts are Inter, Noto Serif, JetBrains Mono (EffectCraft also Noto Sans Symbols 2); there are no PDF backend
  data or Lucide icons. `debian/copyright` and the `.docs` files list these. Neither has man page generators, so the man
  pages are written by hand: check them against `<app>-cli help` after an upgrade.
- FilmCraft's optional `neural-voices` feature is not built (upstream's deb build default).
- **EffectCraft cannot be `cargo vendor`ed**: its Cargo.lock takes the same craft-libs crate (name + version) from several git
  revisions and `cargo vendor` stops with "found duplicate version of package". Its `build.sh fetch` runs `cargo fetch --locked`
  into a private CARGO_HOME instead and snapshots it (`effectcraft-<ver>-cargo-home.tar.xz`, about 600 MB, containing
  `registry/cache`, `git/` and a small license-only `vendor/` made by `snapshot-licenses.py`). `build` unpacks it to
  `<worktree>/cargo-home` and builds offline with that CARGO_HOME. git crates inherit fields from their workspace, so
  `snapshot-licenses.py` writes a resolved Cargo.toml for them.
- `filmcraft-cli` has no `--automation-read-root`/`--automation-write-root` (EffectCraft's has), so its MCP server cannot be confined to a folder.
- `pgrep -f` inside a waiting loop matches the loop's own command line and never ends; wait for the build's own completion notice instead.
