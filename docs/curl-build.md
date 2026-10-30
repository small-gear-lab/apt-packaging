# curl 8.23.0 (HTTP/3) packaging

OpenSSL flavour only, built from the signed upstream tarball on top of Ubuntu's `debian/`.
Version `8.23.0-1~smallgearlab1`, in suite `resolute` (priority 500, so `apt upgrade` takes it as it is
newer than Ubuntu's 8.18.0). Installed on 2026-10-30 (apt upgrade).

## Layout

| Where | What |
|---|---|
| `~/.local/share/apt/packaging/curl/debian/` | source of truth for the packaging |
| `~/.local/share/apt/packaging/curl/build.sh` | `fetch [ver]` (download + verify), `build [ver]` (fresh unpack, build) |
| `~/.cache/curl-dl/orig/` | upstream tarball and `.asc` |
| `~/.cache/curl-dl/deb/build/` | work tree (thrown away on every build) and the debs |
| `~/.cache/curl-dl/log/` | build logs |

## Everyday

```
build.sh fetch 8.24.0           # checks GOODSIG and fingerprint 27EDEAF2...12C2
# bump debian/changelog (new ~smallgearlab1 entry), then
build.sh build 8.24.0 > ~/.cache/curl-dl/log/build.log 2>&1
sgl-reprepro includedeb resolute ~/.cache/curl-dl/deb/build/*_8.24.0-*.deb
sudo apt update && sudo apt upgrade
```

The configure summary ("Configured to build curl/libcurl") is in the log. Check `HTTP3`, `GSASL`,
`NTLM` there before waiting for the build to finish.

## What differs from Ubuntu's 8.18.0 packaging

- HTTP/3: `--with-ngtcp2 --with-nghttp3` (Ubuntu says `--without-...`). It works because OpenSSL is
  3.5 (`libngtcp2-crypto-ossl-dev`). Build-Depends: `libnghttp3-dev`, `libngtcp2-dev`, `libngtcp2-crypto-ossl-dev`.
- Also on: `--enable-httpsrr --enable-ssls-export --enable-proxy-http3` (experimental),
  `--with-libgsasl`, `--enable-ntlm` (opt-in since 8.20.0), `--with-ca-fallback`.
- The CA bundle is a path (`/etc/ssl/certs/ca-certificates.crt`), not embedded: no rebuild when
  `ca-certificates` changes. Do not use `--with-ca-embed`.
- Removed upstream, cannot come back: RTMP (8.20.0), TLS-SRP (8.22.0), SMB (8.23.0). `librtmp-dev` is dropped.
- ECH is off: Ubuntu's OpenSSL 3.5.5 has no ECH API (no `SSL_set1_ech_config_list` in the headers), and
  `./configure --with-openssl --enable-ech` stops with "--enable-ech ignored: No ECH support found" (checked
  2026-10-30), so the flag cannot just be added. Retry when Ubuntu ships an OpenSSL that has it.
- GnuTLS flavour dropped (`libcurl3t64-gnutls`, `libcurl4-gnutls-dev`, `ZZZgnutls-build.patch`, its
  autopkgtests). The patch rewrites `lib/Makefile.am` and stops applying between curl versions.
  Ubuntu's `libcurl3t64-gnutls` stays and keeps serving git and friends. `libcurl4-openssl-dev`
  still `Conflicts: libcurl4-gnutls-dev`.
- The 60-odd CVE patches for 8.18.0 are dropped (upstream has the fixes). Kept: `11_omit-directories-from-config.patch`
  and the krb5 patch, which was regenerated for 8.23.0 (only the line numbers moved).

## Maintenance

- Priority 500 means Ubuntu's security fixes for 8.18.x never apply (their version is lower). Until Ubuntu ships
  8.23+ (`8.23.0-1ubuntu1` beats `~smallgearlab1` on its own), curl security releases come only from us:
  follow upstream (curl.se/docs/security.html) and rebuild.
- No ESM pin is needed: there is no ESM curl, unlike kitty.

## Pitfalls

- **Build in an empty environment** (`env -i`, done by build.sh). The login shell exports
  `LD_RUN_PATH=/usr/local/lib`, which ld turns into `RUNPATH` (lintian: custom-library-search-path),
  plus `LD_LIBRARY_PATH`, `LIBRARY_PATH` and `PKG_CONFIG_PATH`. Unsetting them one by one misses the next.
  The kitty build had the same problem and was fixed the same way in `0.49.2-1~smallgearlab6`
  (`~smallgearlab5` and older carry `RUNPATH /usr/local/lib`).
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
