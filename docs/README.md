# small-gear-lab apt repo

Personal apt repository for this machine (Ubuntu 26.04, `resolute`, amd64). It is a record of how this
one machine is set up, not a general-purpose tool: paths and package choices follow from that.
To reproduce the setup elsewhere, see `../system/README.md` (the files that live outside this tree).

## Layout

```
~/.local/share/apt/
├── docs/                      this directory
├── pubkeys/small-gear-lab.asc public key (644, readable by _apt)
└── repos/small-gear-lab/      reprepro base dir (conf/ db/ dists/ pool/)
```

| Where | What |
|---|---|
| `/etc/apt/sources.list.d/small-gear-lab.sources` | `file:` URI, `Suites: resolute resolute-testing`, `Signed-By` = the public key above |
| `/etc/apt/preferences.d/small-gear-lab` | lowers the ESM pin (510 -> 500) for the kitty packages only, so that they compete on version |
| `~/.local/bin/sgl-reprepro` | runs reprepro with the signing passphrase supplied from a password manager |
| `~/.local/bin/pinentry-secret-tool` | pinentry for rbw: answers the master password from the desktop keyring |
| `~/.gnupg/gpg-agent.conf` | `allow-preset-passphrase` |
| ACL on `~`, `~/.local`, `~/.local/share` | `u:_apt:--x`, so that `_apt` can walk down to the repo |

## Suites

- `resolute` (Suite `stable`): normal. `apt upgrade` takes packages from here.
- `resolute-testing` (Suite `testing`): `NotAutomatic` + `ButAutomaticUpgrades`, so it is opt-in
  (`apt install pkg/resolute-testing`). Currently empty.

The names follow Ubuntu's own `resolute-updates` / `resolute-backports` style, because
reprepro allows only one Codename per distribution stanza.

## Everyday operations

Add or replace packages (signs without a prompt):

```
sgl-reprepro includedeb resolute path/to/*.deb
```

Other reprepro commands work the same way:

```
sgl-reprepro list resolute
sgl-reprepro export            # re-write and re-sign the indices
sgl-reprepro remove resolute kitty
```

Then `sudo apt update` and `apt-cache policy <pkg>`.

reprepro keeps one version per package per suite, so including a newer version
drops the older one from the repo.

## Signing key

- ed25519, sign only, no expiry, protected by a passphrase.
- Fingerprint `35CC 622C 3422 5A22 4B16 DC97 B500 B351 8F99 1E1D`, uid `small-gear-lab apt repository`
  (the keygrip is in `~/.config/sgl-reprepro.conf`; `gpg --list-secret-keys --with-keygrip` shows it).
- The passphrase and the revocation certificate are kept in a password manager, never in this repository.
  Which entry to read is set in `~/.config/sgl-reprepro.conf`.
- If the key is lost: make a new one, re-export `pubkeys/small-gear-lab.asc`, and run
  `sgl-reprepro export`.

How the unattended signing works:

1. `rbw` unlocks itself. Its pinentry is `~/.local/bin/pinentry-secret-tool`, which answers the
   master-password prompt from the desktop keyring (`secret-tool`).
   Any other prompt (e.g. a two-factor code) is passed on to a normal pinentry.
2. `rbw get <item> --field <field>` is piped into `gpg-preset-passphrase --preset <keygrip>`;
   item, field and keygrip come from `~/.config/sgl-reprepro.conf`.
3. reprepro signs. On exit the passphrase is forgotten again (`--forget`).

If `rbw` says it cannot find the entry or `rbw sync` fails with a missing `access_token`,
the login is stale: `rbw purge`, then `rbw login`.

## Version rules

- Our rebuilds carry the suffix `~smallgearlab<N>`, e.g. `0.49.2-1~smallgearlab2`.
- `~` sorts below nothing, so `0.49.2-1~smallgearlab2` is older than a future official
  `0.49.2-1`; the official package takes over by itself.
- Do not put a hyphen in the suffix. The Debian revision is whatever follows the last hyphen.
- Bump `<N>` whenever the content changes. Re-including the same version with different
  content will not upgrade anything that is already installed.

## apt priorities (why the pin file exists)

apt first keeps only the versions with the highest priority, then picks the newest of those.
Ubuntu Pro ESM is pinned at 510, the archive and this repo are at 500, so without the pin file
the older ESM kitty won over our newer one. The pin file lowers ESM to 500 for the kitty
packages only; `Package: *` is deliberately not used.

See also: `kitty-build.md`.

## Desktop entries (kitty)

Two launcher entries are named "kitty": the packaged `/usr/share/applications/kitty.desktop` and the
personal `~/.local/share/applications/kitty-custom.desktop` (pinned in the dock, with
`StartupWMClass=kitty`). To keep only one in the Dock search, `~/.local/share/applications/kitty.desktop`
is a copy of the packaged entry with `NoDisplay=true` added (a user-level file of the same name
replaces the system one completely; it is not merged). It does not follow later changes of the
packaged entry. Remove it to get the second icon back.

(`/usr/share/applications/kitty.desktop.bak` from 2024 is a stray backup, owned by no package and
ignored by launchers.)
