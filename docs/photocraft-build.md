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
