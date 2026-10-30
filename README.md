# small-gear-lab apt

A personal apt repository for one Ubuntu 26.04 (`resolute`, amd64) machine, and the recipes that build
its packages. It is a record of how that machine is set up, kept so that the setup can be rebuilt; it is
not a general-purpose tool.

| Where | What |
|---|---|
| `docs/` | how the repository works, and one build note per package family (`kitty-build.md`, `curl-build.md`, `rustls-build.md`) |
| `packaging/` | one directory per package: `build.sh` and the `debian/` tree it builds from |
| `pubkeys/` | the public key that signs the repository |
| `repos/small-gear-lab/conf/` | reprepro's configuration (the generated `db/`, `dists/` and `pool/` are not kept) |
| `system/` | the files that live outside this tree (scripts, apt and gpg-agent settings) and how to install them |
| `scripts/` | `check-publishable.sh`: looks for secrets and private details before anything is published |

Packages built here:

- `kitty` 0.49.2 with a few IME patches, and the `kitty-slang-compiler` it needs to build
- `curl` 8.23.0 with HTTP/3 (ngtcp2 + nghttp3), in two flavours: `curl-openssl` on top of Ubuntu's OpenSSL 3.5, and
  `curl-rustls` with Rustls (Encrypted Client Hello, but no NTLM, pinning or `--capath`). `curl` and `libcurl4t64`
  are metapackages that pick one of them. The flavours are in `resolute-testing`.
- `rustls-ffi-quic` (`librustls-quic`): rustls-ffi with a C API over `rustls::quic`, from
  <https://github.com/small-gear-lab/rustls-ffi-quic>, and `ngtcp2-crypto-rustls`, the ngtcp2 helper that uses
  it. Both are what the Rustls flavour of curl needs for HTTP/3. Also in `resolute-testing`.
- `rustls-ffi` 0.15.7 as upstream has it (not used by the packages above)

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
