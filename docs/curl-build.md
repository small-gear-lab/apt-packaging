# curl 8.23.0 (HTTP/3) packaging

Two flavours from one source, built from the signed upstream tarball on top of Ubuntu's `debian/`: **OpenSSL**
(`curl-openssl`) and **Rustls** (`curl-rustls`). `curl` and `libcurl4t64` are metapackages that pick one.

| Suite | Version | What |
|---|---|---|
| `resolute` (priority 500) | `8.23.0-1~smallgearlab2` | OpenSSL only, the old layout (`curl`, `libcurl4t64` are real packages). `apt upgrade` takes it. |
| `resolute-testing` (priority 100) | `8.23.0-1~smallgearlab6` | both flavours, the layout below. Only for `apt install -t resolute-testing ...`. |

The Rustls flavour was installed on this machine on 2026-10-30 (see "Switching").

## The packages

| Package | What |
|---|---|
| `curl` (metapackage, `all`) | `Depends: curl-openssl \| curl-rustls` |
| `libcurl4t64` (metapackage, `any`) | `Depends: libcurl4t64-openssl (= ver) \| libcurl4t64-rustls (= ver)`; **`Provides: libcurl4 (= ver)`** |
| `curl-openssl`, `curl-rustls` | `/usr/bin/curl`, `wcurl`, completions. Conflict with each other. |
| `libcurl4t64-openssl`, `libcurl4t64-rustls` | `libcurl.so.4`. Conflict with each other. |
| `libcurl4-openssl-dev`, `libcurl4-rustls-dev` | headers, `libcurl.so`, `libcurl.a`, `curl-config`, `libcurl.pc`. Conflict with each other (and with `libcurl4-gnutls-dev`). |
| `libcurl4-doc` | documentation, built from the OpenSSL tree |

Why a metapackage: other packages depend on the **name** `libcurl4t64` and use the **file** `libcurl.so.4`, and a
file can belong to one package at a time. The metapackage keeps the name; the flavours own the file. Two things make
switching invisible to the packages that use libcurl:

- The shlibs of `libcurl.so.4` (a file in each flavour: `libcurl4t64-*.shlibs`) say `libcurl 4 libcurl4t64 (>= 8.23.0)`,
  so programs built against either flavour depend on `libcurl4t64`.
- The Rustls flavour exports the same symbol version tag as the OpenSSL one: `--enable-versioned-symbols=OPENSSL_`
  gives `CURL_OPENSSL_4` (102 symbols in both; checked with `objdump -T`). Programs linked against `libcurl.so.4`
  look the symbols up with that tag. `ldd -r` on cmake, obs, LibreOffice shows no undefined symbol with the Rustls one.

`libcurl4t64` has to **provide `libcurl4`**, as Ubuntu's real `libcurl4t64` does: `sublime-merge` depends on
`libcurl3 | libcurl4`, and `apt-get -s` showed it would be removed without it (`~smallgearlab4` fixed that).
The lintian warnings `distant-prerequisite-in-shlibs` and `package-name-doesnt-match-sonames` of the two library
packages are overridden for this reason.

`libcurl.symbols.openssl-reference` is Ubuntu's `libcurl4t64.symbols`, kept for reference: the flavours have no
symbols file of their own (it would bind other packages to a flavour).

## The Rustls flavour

- TLS by Rustls (`rustls-ffi-quic`, packages `librustls-quic0.15.7` and `-dev`), HTTP/3 by ngtcp2 with the helper
  `libngtcp2-crypto-rustls` (see `packaging/ngtcp2-crypto-rustls`). **Encrypted Client Hello** works, over HTTP/3 too.
- **It has no NTLM** (`--ntlm`: the NTLM code needs DES from a TLS library) and none of the OpenSSL-only options
  (`--enable-proxy-http3`, `--with-ca-fallback`). The CA is `/etc/ssl/certs/ca-certificates.crt`, read at run time.
- **`--pinnedpubkey` works**, over TCP and over HTTP/3 (`rustls-pinned-public-key.patch`, and `-quic.patch` for HTTP/3:
  the certificate comes from `ngtcp2_crypto_rustls_session_peer_certificate`, which has it from
  `rustlsq_quic_connection_peer_certificate`). The backend needed a `sha256sum`: without one `Curl_pin_peer_pubkey`
  fails every `sha256//` pin. A pin on a connection whose certificate cannot be had fails; it is never ignored.
- **`--capath` works** (`rustls-capath.patch`): the PEM files of the directory are read into the root store when the
  config is built (Rustls has no lookup by name). Only a directory that the application sets itself is read: the one that
  `configure` names (`--with-ca-path`, `/etc/ssl/certs`) is not, as it holds what the bundle holds and would add to the
  CAs that `--cacert` chose. As with OpenSSL, `--capath` adds to the default bundle; `--cacert X --capath Y` trusts X and Y.
- No session resumption and no 0-RTT over QUIC yet: every connection does the full handshake.
- `curl -V` says `rustls-ffi/0.15.7/rustls/0.23.46/aws-lc-rs ... ngtcp2/1.16.0 nghttp3/1.12.0`, features `ECH HTTP3`.
- The patches are `debian/patches/rustls-http3-ngtcp2-quic.patch` (9 files), `rustls-capath.patch` and
  `rustls-pinned-public-key.patch` (both in `lib/vtls/rustls.c`; the second also in `rustls.h` and `vquic-tls.c`) and
  `rustls-pinned-public-key-quic.patch` (`vquic-tls.c`). The first splits `cr_build_config()` out of
  `lib/vtls/rustls.c` so that the QUIC filter can build the client config, adds the Rustls branch of `vquic-tls.[ch]`
  and `cf-ngtcp2*.[ch]`, and teaches `configure` the pkg-config module `rustls-quic` (functions `rustlsq_*`; the
  header maps the names of rustls-ffi to them) before `rustls`. Against plain rustls-ffi it builds as before, without
  QUIC. The CMake build is not covered.

Checks that were made on the built debs (from `dpkg-deb -x`, and then installed):

```
curl --http3-only -s -o /dev/null -w '%{http_code} %{http_version}\n' https://www.google.com/     # 200 3
curl --http3-only -s --doh-url https://1.1.1.1/dns-query --ech true https://cloudflare-ech.com/cdn-cgi/trace | rg '^(sni|http)='
        # sni=encrypted, http=http/3
curl --http3-only --cacert <a CA that does not match> https://cloudflare.com/                       # exit 60
curl --pinnedpubkey sha256//<hash of the key> https://localhost:18443/    # a local `openssl s_server`: 200; a wrong hash: exit 90
curl --http3-only --pinnedpubkey sha256//<the hash curl prints> https://cloudflare.com/   # 301; a wrong hash: exit 90
curl --cacert <unrelated> --capath <dir with the system bundle> https://example.com/   # 200; the same with an empty dir: exit 60
```
The pin of a public server can differ from what `openssl s_client` shows: a CDN may answer with an RSA or an ECDSA
certificate, depending on the client. Try pinning against a server of your own.

## Switching

Nothing is installed by `apt upgrade`: testing has priority 100.

```
# check what apt would do (no root needed after `sudo apt update`)
apt-get -s install -t resolute-testing curl-rustls libcurl4t64-rustls libcurl4-rustls-dev

# the Rustls flavour
sudo apt install -t resolute-testing curl-rustls libcurl4t64-rustls libcurl4-rustls-dev
# back to OpenSSL (this direction is not tried on a real system yet)
sudo apt install -t resolute-testing curl-openssl libcurl4t64-openssl libcurl4-openssl-dev
```

Name the `-dev` package too: `libpoppler-dev` depends on `libcurl4-gnutls-dev | libcurl-dev`, and without it apt may
pick Ubuntu's `libcurl4-gnutls-dev`. Before an upgrade or a switch, look at the simulation for **`Remv` lines**: that is
how the `libcurl4` Provides was found.

Done on 2026-10-30: from `curl 8.23.0-1~smallgearlab1` (OpenSSL) straight to the Rustls flavour of `~smallgearlab4`;
`dpkg --audit` clean, `sublime-merge` kept, `ldd -r` of cmake, obs, LibreOffice clean, PHP's curl extension reports
`rustls-ffi/...`. git uses Ubuntu's `libcurl-gnutls` and is not affected.

## Layout

| Where | What |
|---|---|
| `~/.local/share/apt/packaging/curl/debian/` | source of truth for the packaging |
| `~/.local/share/apt/packaging/curl/build.sh` | `fetch [ver]` (download + verify), `build [ver]` (fresh unpack, build), `check-copyright [ver]` |
| `~/.cache/curl-dl/orig/` | upstream tarball and `.asc` |
| `~/.cache/curl-dl/deb/build/` | work tree (thrown away on every build) and the debs |

`debian/rules` configures and builds each flavour in `debian/build-<flavour>/` and installs it into `debian/tmp`
(OpenSSL) and `debian/tmp-rustls`. `CONFIGURE_ARGS` are shared, `CONFIGURE_ARGS_openssl` and
`CONFIGURE_ARGS_rustls` are the flavours' own. Profiles `pkg.curl.no-openssl` and `pkg.curl.no-rustls` leave a
flavour out.

## Everyday

Order of builds, because each needs the previous one **installed** (Build-Depends; the debs are in `resolute-testing`):

1. `packaging/rustls-ffi-quic` (`librustls-quic-dev`)
2. `packaging/ngtcp2-crypto-rustls` (`libngtcp2-crypto-rustls-dev`; also needs Ubuntu's `libngtcp2-dev`)
3. `packaging/curl`

```
build.sh fetch 8.24.0           # checks GOODSIG and fingerprint 27EDEAF2...12C2
# bump debian/changelog (new ~smallgearlab1 entry), refresh the patches if they do not apply, then
build.sh build 8.24.0 > ~/.cache/curl-dl/build.log 2>&1
lintian --tag-display-limit 0 ~/.cache/curl-dl/deb/build/curl_8.24.0-*.changes
sgl-reprepro includedeb resolute-testing ~/.cache/curl-dl/deb/build/*_8.24.0-*.deb
sudo apt update
```

Registering the same version again does not work in reprepro: **bump `~smallgearlabN`** whenever the content of a
deb changes (or `sgl-reprepro remove <suite> <packages>` first, for testing only). The configure summary
("Configured to build curl/libcurl") is in the log; check `HTTP3`, `ECH` (Rustls) and `NTLM` (OpenSSL) there before
waiting for the build to finish.

## What differs from Ubuntu's 8.18.0 packaging

- HTTP/3: `--with-ngtcp2 --with-nghttp3` (Ubuntu says `--without-...`). The OpenSSL flavour works because OpenSSL is
  3.5 (`libngtcp2-crypto-ossl-dev`). Build-Depends: `libnghttp3-dev`, `libngtcp2-dev`, `libngtcp2-crypto-ossl-dev`,
  and for the Rustls flavour `libngtcp2-crypto-rustls-dev`, `librustls-quic-dev`.
- Also on (both): `--enable-httpsrr --enable-ssls-export` (experimental), `--with-libgsasl`. OpenSSL only:
  `--enable-proxy-http3`, `--enable-ntlm` (opt-in since 8.20.0), `--with-ca-fallback`. Rustls only: `--enable-ech`.
- The CA bundle is a path (`/etc/ssl/certs/ca-certificates.crt`), not embedded: no rebuild when
  `ca-certificates` changes. Do not use `--with-ca-embed`.
- Removed upstream, cannot come back: RTMP (8.20.0), TLS-SRP (8.22.0), SMB (8.23.0). `librtmp-dev` is dropped.
- ECH: the OpenSSL flavour has none. Ubuntu's OpenSSL 3.5.5 has no ECH API (no `SSL_set1_ech_config_list` in the
  headers), and `./configure --with-openssl --enable-ech` stops with "--enable-ech ignored: No ECH support found"
  (checked 2026-10-30). The Rustls flavour is the way to ECH.
- GnuTLS flavour dropped (`libcurl3t64-gnutls`, `libcurl4-gnutls-dev`, `ZZZgnutls-build.patch`, its
  autopkgtests). The patch rewrites `lib/Makefile.am` and stops applying between curl versions.
  Ubuntu's `libcurl3t64-gnutls` stays and keeps serving git and friends. Both `-dev` packages
  `Conflicts: libcurl4-gnutls-dev`.
- The 60-odd CVE patches for 8.18.0 are dropped (upstream has the fixes). Kept: `11_omit-directories-from-config.patch`
  and the krb5 patch, which was regenerated for 8.23.0 (only the line numbers moved).

## Maintenance

- Priority 500 means Ubuntu's security fixes for 8.18.x never apply (their version is lower). Until Ubuntu ships
  8.23+ (`8.23.0-1ubuntu1` beats `~smallgearlab1` on its own), curl security releases come only from us:
  follow upstream (curl.se/docs/security.html) and rebuild.
- No ESM pin is needed: there is no ESM curl, unlike kitty.
- A new curl: the patch `rustls-http3-ngtcp2-quic.patch` has to apply (it touches `lib/vtls/rustls.c`, which upstream
  changes often) and the Rustls code has to keep working with the `vquic` interfaces; try the checks above.
- A new ngtcp2 in Ubuntu: rebuild `ngtcp2-crypto-rustls` (it is built from ngtcp2's `crypto/shared.c`, taken from
  Ubuntu's source of the same version).
- A new rustls-ffi release: `downstream/update-upstream.sh` in `rustls-ffi-quic`, then the packaging (see its
  `docs/design.md`, "Following upstream"). The soname carries the whole version, so the package name changes.

## Pitfalls

- **Build in an empty environment** (`env -i`, done by build.sh). The login shell exports
  `LD_RUN_PATH=/usr/local/lib`, which ld turns into `RUNPATH` (lintian: custom-library-search-path),
  plus `LD_LIBRARY_PATH`, `LIBRARY_PATH` and `PKG_CONFIG_PATH`. Unsetting them one by one misses the next.
  The kitty build had the same problem and was fixed the same way in `0.49.2-1~smallgearlab6`
  (`~smallgearlab5` and older carry `RUNPATH /usr/local/lib`).
- `build.sh` must keep its `key_fpr=...` on line 26: `.gitleaksignore` names that line.
- `libcurl4-doc.docs`: `docs/INTERNALS.md` moved to `docs/internals/` in 8.23.0. A new upstream may move
  other listed docs; `dh_installdocs` fails with "Cannot find (any matches for)".
- Check the first build's failures at `dh_installdocs` / `dh_install`: the compile itself takes a few minutes and passes first.
- `bad-whatis-entry` for `libcurl-symbols.3` in lintian is upstream's and harmless.
- Check a built deb without installing it: `dpkg-deb -x`, then
  `env -i LD_LIBRARY_PATH=<x>/usr/lib/x86_64-linux-gnu <x>/usr/bin/curl -V`.
- This machine used to carry a self-built curl under `~/.local/opt/curl` that programs picked up through
  `PATH`, `PKG_CONFIG_PATH` and `LD_LIBRARY_PATH` (set in the shell's `.zshenv`) and a systemd user override.
  It was deleted on 2026-10-30 once those references were gone. `systemctl --user` keeps the environment it
  was given at login: after changing the shell's startup files, run `systemctl --user set-environment` /
  `unset-environment` (or log in again), otherwise services keep loading the old library. Processes started
  before the change keep the old mapping until they are restarted.
