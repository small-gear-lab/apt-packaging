# small-gear-lab apt

A personal apt repository for one Ubuntu 26.04 (`resolute`, amd64) machine, and the recipes that build
its packages. It is a record of how that machine is set up, kept so that the setup can be rebuilt; it is
not a general-purpose tool.

| Where | What |
|---|---|
| `docs/` | how the repository works, and one build note per package family (`kitty-build.md`, `curl-build.md`, `rustls-build.md`, `openssl4-build.md`, `mozc-build.md`, `neovim-build.md`, `neovide-patched.md`, `aria2-build.md`) |
| `packaging/` | one directory per package: `build.sh` and the `debian/` tree it builds from |
| `pubkeys/` | the public key that signs the repository |
| `repos/small-gear-lab/conf/` | reprepro's configuration (the generated `db/`, `dists/` and `pool/` are not kept) |
| `system/` | the files that live outside this tree (scripts, apt and gpg-agent settings) and how to install them |
| `scripts/` | `check-publishable.sh`: looks for secrets and private details before anything is published |

Packages built here:

- `kitty` 0.51.0 with a few IME patches and a local status-symbol option, and the `kitty-slang-compiler` it needs to
  build; `fonts-sgl-status-icons` is the font that option uses
- `curl` 8.23.0 with HTTP/3 (ngtcp2 + nghttp3), in two flavours: `curl-openssl` on top of Ubuntu's OpenSSL 3.5, and
  `curl-rustls` with Rustls (Encrypted Client Hello, `--capath` and `--pinnedpubkey`; no NTLM). `curl` and `libcurl4t64`
  are metapackages that pick one of them. The flavours are in `resolute-testing`.
- `rustls-ffi-quic` (`librustls-quic`): rustls-ffi with a C API over `rustls::quic`, from
  <https://github.com/small-gear-lab/rustls-ffi-quic>, and `ngtcp2-crypto-rustls`, the ngtcp2 helper that uses
  it. Both are what the Rustls flavour of curl needs for HTTP/3. Also in `resolute-testing`.
- `rustls-ffi` 0.15.7 as upstream has it (not used by the packages above)
- `mozc` 3.35.6354 with the UT dictionaries merged into the system dictionary (`mozc-server`, `mozc-data`,
  `mozc-utils-gui`, `fcitx5-mozc`, `fcitx-mozc-data`, `ibus-mozc`, `emacs-mozc`, `emacs-mozc-bin`), built with Bazel from
  the `debian/` of phoepsilonix/mozc-deb; no fcitx4 package. Ubuntu has 2.29 without UT dictionaries
- `neovim` and `neovim-runtime` 0.12.6: Ubuntu's 0.11.6 packaging carried over to the newer upstream release, built
  without the test suite and with the tree-sitter grammars that upstream pins (Ubuntu's `tree-sitter-*-src`
  packages are older than what the 0.12 runtime queries expect)
- `neovide` 0.17.2 and `tree-sitter-cli` 0.27.2: repacks of the official release binaries, checked against the sha256
  digest GitHub reports for each asset. `tree-sitter-cli` has Ubuntu's package name with a newer version, because
  nvim-treesitter needs 0.26.1 or later to build parsers. `resolute-testing` also has a `neovide` built from source
  with a patch series (see `docs/neovide-patched.md`)
- `aria2` 1.37.0 with SOCKS5 proxy support (Ubuntu's packaging plus one patch)
- `libssl4`: only the OpenSSL 4 runtime libraries, which Ubuntu 26.04 does not have (needed by the mainline kernel headers)
- `clang`, `llvm`, `lld`, `lldb` and the other unversioned LLVM names: `llvm-defaults` meta packages that follow LLVM 24
  (apt.llvm.org's still point at 23). In `resolute-testing`
- `gemini-api-cli` 0.4.6: repack of the official `gemini-api` release binary
- fonts: `fonts-shippori-mincho`, `storytold-craft-fonts` (a metapackage) and `fonts-sgl-status-icons`
- `storytold-photocraft` and `photocraft-cli`: the PhotoCraft image editor and its CLI, built from the upstream tag. In
  `resolute-testing`

Start with `docs/README.md`.

Before publishing, run `scripts/check-publishable.sh` (needs `gitleaks` and `ripgrep`). It scans the tree and
the history, and checks the commit addresses. The strings it must not find are listed in a local file kept out
of the repository; `scripts/check-publishable.patterns.example` shows the format.

## License

The scripts, notes and configuration written for this repository are licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option. See [NOTICE](NOTICE) for the attribution and for the third-party files below.

This does **not** cover the third-party material in `packaging/*/debian/`. Those trees start from
Ubuntu's and Debian's packaging and keep their own licenses: read `debian/copyright` and the headers of
the files in `debian/patches/`. The two IME patches written here for kitty (`0016`, `0017`) change kitty's
own source and have no header of their own; treat them as covered by kitty's license, GPL-3.0-only.
`0015` only adapts a Debian patch (one line of `go.mod`).
