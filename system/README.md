# system/ — the files that live outside this tree

The repository itself (`repos/`, `packaging/`, `pubkeys/`) is only half of the setup. These are the other
half: scripts, one gpg-agent setting and the two apt files. They are copies; the working versions live
at the destinations below.

| Here | Goes to | What it is |
|---|---|---|
| `bin/sgl-reprepro` | `~/.local/bin/sgl-reprepro` | runs reprepro and signs without a prompt (passphrase from a password manager) |
| `bin/pinentry-secret-tool` | `~/.local/bin/pinentry-secret-tool` | pinentry for rbw: answers its master-password prompt from the desktop keyring |
| `sgl-reprepro.conf.example` | `~/.config/sgl-reprepro.conf` (mode 600) | which key and which password-manager entry to use; **not** in this repository |
| `gnupg/gpg-agent.conf` | `~/.gnupg/gpg-agent.conf` | `allow-preset-passphrase`, so that gpg-preset-passphrase can seed the cache |
| `apt/small-gear-lab.sources.in` | `/etc/apt/sources.list.d/small-gear-lab.sources` | the repository as an apt source (`@HOME@` is replaced) |
| `apt/preferences.d/small-gear-lab` | `/etc/apt/preferences.d/small-gear-lab` | lowers Ubuntu ESM's pin for the kitty packages only |

## Installing

```
install -m 755 system/bin/sgl-reprepro system/bin/pinentry-secret-tool ~/.local/bin/
install -m 600 system/sgl-reprepro.conf.example ~/.config/sgl-reprepro.conf   # then edit it
cat system/gnupg/gpg-agent.conf >> ~/.gnupg/gpg-agent.conf && gpgconf --kill gpg-agent
sed "s|@HOME@|$HOME|g" system/apt/small-gear-lab.sources.in | sudo tee /etc/apt/sources.list.d/small-gear-lab.sources
sudo install -m 644 system/apt/preferences.d/small-gear-lab /etc/apt/preferences.d/
rbw config set pinentry ~/.local/bin/pinentry-secret-tool
```

apt reads a `file:` repository as the `_apt` user, which must be able to walk down to it:

```
setfacl -m u:_apt:--x ~ ~/.local ~/.local/share
```

## What is deliberately not here

- The signing key (it stays in `~/.gnupg`) and its passphrase (it stays in the password manager).
- The values in `~/.config/sgl-reprepro.conf`: the keygrip and the name of the password-manager entry.
- The generated repository (`repos/*/db`, `dists`, `pool`): rebuild it from `packaging/*/build.sh`.
