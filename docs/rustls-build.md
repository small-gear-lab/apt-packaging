# Rustls packages (rustls-ffi, rustls-ffi-quic, ngtcp2-crypto-rustls)

What the Rustls flavour of curl (see `curl-build.md`) is made of. All three are in `resolute-testing`; none is needed
by anything else, and none is installed by `apt upgrade`.

| Source package | Binary packages | Version | Built from |
|---|---|---|---|
| `rustls-ffi` | `librustls0.15.7`, `librustls-dev` | `0.15.7-1~smallgearlab1` (in `resolute`) | the upstream release tag, <https://github.com/rustls/rustls-ffi> |
| `rustls-ffi-quic` | `librustls-quic0.15.7`, `librustls-quic-dev` | `0.15.7+quic1-1~smallgearlab2` | a tag of <https://github.com/small-gear-lab/rustls-ffi-quic> (`REV` names it) |
| `ngtcp2-crypto-rustls` | `libngtcp2-crypto-rustls0`, `-dev` | `1.16.0-1~smallgearlab1` | Ubuntu's ngtcp2 1.16.0 source and `src/` of the packaging |

`rustls-ffi` is the library as upstream has it (curl's `--with-rustls` works against it; no QUIC). curl does not use it
any more, the Rustls flavour uses `librustls-quic`. The two libraries can be installed together: the exported
functions of `librustls_quic` are `rustlsq_*`, the headers are in `/usr/include/rustls-quic/`.

## Building

The environment is the builder's own business (cargo, cargo-c, cmake, a C compiler; the checks are in `build.sh`): none
of it is a dependency of the installed packages. The Rust toolchain is rustup's, not Ubuntu's; `build.sh` compares the
highest `rust-version` of the linked crates with the installed `rustc` and stops when it is older.

```
cd packaging/rustls-ffi-quic
build.sh fetch v0.15.7+quic1   # source tarball of that tag, then `cargo vendor` (needs the network); writes REV
build.sh build                 # fresh unpack, offline build, lintian-clean
sgl-reprepro includedeb resolute-testing ~/.cache/rustls-ffi-quic-dl/deb/build/*_<version>-*.deb
```

`packaging/rustls-ffi` is the same with `fetch [version]` from the upstream tag (the tarball must be the commit the
tag points at; its sha256 is recorded in `SHA256SUMS` on first use). `packaging/ngtcp2-crypto-rustls` does
`apt-get source --download-only ngtcp2` and needs `librustls-quic-dev` and `libngtcp2-dev` installed.

- **Licenses of the Rust crates** (22 are linked in): `packaging/rustls-ffi/gen-crate-licenses.py` (shared by the two
  Rust packages) copies the license files of each linked crate into the package and writes a paragraph for each into
  `debian/copyright`. It stops for a crate whose license it cannot settle, so a new upstream cannot slip one past.
- **Soname = package name**: the soname carries the whole upstream version (`librustls_quic.so.0.15.7`), so every
  release is a new package name (`@SOVER@` in the file names is replaced by `build.sh`).
- **No static library** (40 MB), **no `-dbgsym`** (the release profile has no debug information).
- `rustls-ffi-quic`: take a tag **before** building (`v0.15.7+quic1`; the counter goes up when the same upstream
  release is built from a new commit), and `REV` has two lines: the tag, and the commit it pointed at.
- Version rule as everywhere here: `~smallgearlabN` goes up whenever the content of a deb changes.

## Checks

```
lintian --tag-display-limit 0 *.changes           # all three: no E/W
nm -D --defined-only librustls_quic.so | rg -c ' T rustls_'   # 0: nothing with the names of rustls-ffi
nm -D libcurl.so.4 | rg ' U rustls'                           # only rustlsq_*
```

`ngtcp2-crypto-rustls` is a shared library of two files compiled together (`crypto/shared.c` of ngtcp2, and
`src/ngtcp2_crypto_rustls.c`, derived from ngtcp2's quictls helper); the packet protection is OpenSSL's libcrypto.
Its Depends are `libngtcp2-16`, `librustls-quic0.15.7`, `libssl3t64`.
