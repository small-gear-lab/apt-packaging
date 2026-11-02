# libssl4 (OpenSSL 4 runtime) packaging

Only the runtime libraries of OpenSSL 4 (`libssl.so.4`, `libcrypto.so.4`), as the package `libssl4`, in suite
`resolute`. Ubuntu 26.04 ships OpenSSL 3.5 (`libssl3t64`) and has no `libssl4`.

| Package | Version | Suite |
|---|---|---|
| `libssl4` | `4.0.3-1ubuntu1~smallgearlab1` | `resolute` |

## Why

The kernel headers of the Ubuntu mainline builds (https://kernel.ubuntu.com/mainline/, the `mainline` tool) are built
on Ubuntu's development series, which has OpenSSL 4. `linux-headers-<ver>-generic` therefore says
`Depends: ... libssl4 (>= 4.0.0)`, because its host tool `scripts/sign-file` is linked with `libcrypto.so.4`.
On resolute that dependency cannot be met: `apt --fix-broken install` removed the headers package on 2026-11-02 (the
kernel image and modules have no such dependency, so the kernel itself was fine). Without the headers DKMS cannot build
for that kernel. With `libssl4` the headers install, and `sign-file` runs.

`sign-file` is the only binary in the 7.3.1 headers that needs OpenSSL 4 (checked with `ldd` on every ELF in it).

## What is built, and what is left out

Source: Ubuntu's `openssl 4.0.3-1ubuntu1` (stonking/tenacious), `debian/` copied to `packaging/openssl4/debian/`
and cut down. The orig tarball is verified against OpenSSL's release key (`debian/upstream/signing-key.asc`,
fingerprint `C46ED3F2CBEFDA1FDAADA44264ED7B1DCCE71CB2`) by `build.sh fetch`, and its SHA256 matched the one on the
GitHub release page.

- **Only `libssl4` is built.** `openssl`, `openssl-provider-legacy`, `libssl-dev` and the others have the same names as the
  OpenSSL 3.5 packages of resolute, and the 4.x ones would replace them (and the `ossl-modules/legacy.so` of 3.5 is
  the same path). That would pull the whole system to OpenSSL 4.
- `libssl4` does not depend on `openssl-provider-legacy` (upstream's does).
- The udebs, the autopkgtests and the `rules` overrides for the dropped packages are gone; `override_dh_missing` only lists.
- No `libssl-dev` here: nothing needs the headers of OpenSSL 4. If something ever does, do not build it under that
  name; a differently named `-dev` would be needed.

`libssl4` installs next to `libssl3t64` (different sonames, different files). `/etc/ssl/openssl.cnf` belongs to the
`openssl` 3.5 package; a program linked with OpenSSL 4 reads it too (`--openssldir=/usr/lib/ssl`, which points there).
Only `sign-file` links with it today; whether it reads that file was not checked.

## Rebuild

```
~/.local/share/apt/packaging/openssl4/build.sh fetch      # source + signature check
~/.local/share/apt/packaging/openssl4/build.sh build      # needs libjitterentropy3-dev
sgl-reprepro includedeb resolute ~/.cache/openssl4-dl/deb/build/libssl4_*.deb
```

Build dependency: `libjitterentropy3-dev` (in resolute; Ubuntu's rules use `enable-jitter`). The tests are skipped
(`nocheck`). Lintian is clean.

For a newer upstream version: `pull-lp-source` the new source, diff its `debian/` against ours, carry the changes over,
raise `~smallgearlabN`, and pass the version to `build.sh`.

## Installing the mainline headers

The mainline `.deb` files are in `~/.cache/mainline/<ver>/` after `mainline install`. A copy of 7.3.1 is in
`~/.cache/kernel-deb-backup/7.3.1-070301/`. A headers package that was removed can be put back from there:

```
sudo apt install -y /path/to/linux-headers-<ver>-generic_*_amd64.deb      # libssl4 comes from this repo
```

Do this *before* the next `apt --fix-broken install`, or the broken package is removed again.

## Things to keep in mind

- OpenSSL 4 is now a second line of security updates that nobody delivers here. `libssl4` is only for the headers' host
  tool; do not link anything else against it.
- If Ubuntu puts its own `libssl4` into resolute, it is `4.0.x-...ubuntu...` without the `~smallgearlab` suffix and
  replaces ours by itself.
