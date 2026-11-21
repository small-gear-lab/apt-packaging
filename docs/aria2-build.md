# aria2 1.37.0 + SOCKS5 packaging

Ubuntu's `aria2 1.37.0+debian-4` (GnuTLS, c-ares, `--enable-libaria2`) plus one patch: SOCKS5 proxy support for
HTTP/HTTPS/FTP/SFTP (`socks5://` and `socks5h://` in `--all-proxy` and friends). Nothing else differs from the
Ubuntu package.

| Suite | Version | What |
|---|---|---|
| `resolute` (priority 500) | `1.37.0+debian-4+smallgearlab2` | `aria2`, `libaria2-0`, `libaria2-0-dev`. `apt upgrade` takes it. |

Installed on this machine on 2026-11-18, replacing a hand-built `~/.local/bin/aria2c` (symlink into
`~/work/forks/aria2`) that had stopped starting after the 24.04 -> 26.04 upgrade (`libxml2.so.2` is `libxml2.so.16`
now). The checkout is still there but nothing on `PATH` points at it.

## The patch

`debian/patches/socks5-proxy.patch` is commit `08c6ed3a` of the author's fork (branch
`feat/add-socks-proxy-support`) with a DEP-3 header. The fork is based on upstream master (42 commits after
1.37.0); the patch applies to 1.37.0 without offsets or fuzz. It touches `src/Makefile.am` and `test/Makefile.am`,
so the build needs `dh_autoreconf`, which compat 13 does by default.

## Version name: `+smallgearlab1`, not `~smallgearlab1`

Every other package here uses `~smallgearlab<N>`, because its upstream version is newer than Ubuntu's. Here the
upstream version is the same (`1.37.0+debian`), and `~` sorts below nothing, so
`1.37.0+debian-4~smallgearlab1` would be *older* than Ubuntu's `1.37.0+debian-4` and apt would never pick it.
With `+` it is above `-4` and below any later official revision (`-5` and up): then `apt upgrade` goes back to
the official package on its own, and **the SOCKS5 patch is lost** unless packaging is moved onto that version.

No pin file is needed (no ESM aria2). Both repos are at 500 and the version decides.

## `aria2` depends on `libaria2-0 (= ${binary:Version})`

The binary package `aria2` is only a thin `aria2c`; option parsing, the proxy handling and the connection code
are all in `libaria2.so.0`. shlibs would only generate `libaria2-0 (>= 1.37.0+debian)`, which Ubuntu's
unpatched `libaria2-0` satisfies, giving a patched `aria2c` over an unpatched library: `--all-proxy=socks5://...`
fails with `unrecognized proxy format` (`OptionHandlerImpl.cc:520`). `debian/control` therefore pins the
library to the same build with `=`. (A `>=` would also reject today's Ubuntu `-4`, but a future official `-5`
would satisfy it and silently drop the patch.)

Testing a built deb by unpacking it (`dpkg-deb -x`) and running its `aria2c` has the same trap: it loads the
*installed* `libaria2.so.0`. Unpack `libaria2-0` too and set `LD_LIBRARY_PATH` to it.

## Build

```
~/.local/share/apt/packaging/aria2/build.sh fetch                 # orig tarball from Ubuntu's deb-src (apt-get source)
~/.local/share/apt/packaging/aria2/build.sh build                 # -> ~/.cache/aria2-dl/deb/build/
sgl-reprepro includedeb resolute ~/.cache/aria2-dl/deb/build/*smallgearlab<N>_amd64.deb
sudo apt-get update && sudo apt-get install aria2 libaria2-0
```

`debian/` in the packaging directory is the source of truth: Ubuntu's `debian/` plus `socks5-proxy.patch`, the
`libaria2-0` dependency and a `+smallgearlab<N>` changelog entry. The work tree is thrown away on every build, and
the build runs under `env -i` (see `curl-build.md`). Registering the same version twice does not work in
reprepro: bump `+smallgearlab<N>` whenever the content of a deb changes. `/etc/apt/sources.list.d/ubuntu.sources`
needs `deb-src` (it has it).

Build log notes (full log read on 2026-11-18, no diagnostics from the SOCKS files): the only compiler warnings are
upstream's (`__DATE__`/`__TIME__`, and c-ares' deprecated `ares_init`, `ares_gethostbyname`, ...). The
"LTO ... cgo" notes are Ubuntu's own.

## Moving to a new Ubuntu version or a new aria2

- Ubuntu bumps `-4` -> `-5` (or a newer upstream): `build.sh fetch`, copy the new `debian/` over the packaging
  directory, put `socks5-proxy.patch` (and its line in `debian/patches/series`) and the `libaria2-0` `=`
  dependency back, add a changelog entry `<ubuntu version>+smallgearlab1`. Check the patch still applies; if
  upstream merged SOCKS5 support itself, drop the patch and this package.
- A rebuilt library can break a hand-built binary the way it did here. Do not put a hand-built aria2 in
  `~/.local/bin` again; build the deb.

## Not tested

A real SOCKS5 server (the proxy format is accepted, a refused connection is reported). The fork has
`Socks5HandshakeTest` and `OptionHandlerTest` for the handshake and parsing, but `DEB_BUILD_OPTIONS=nocheck`
skips the test suite in this build.
