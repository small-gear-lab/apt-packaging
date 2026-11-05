# Working on this repository

A personal apt repository for one Ubuntu 26.04 (`resolute`, amd64) machine, and the recipes that build its
packages. `README.md` says what is in it; `docs/README.md` is the way into how it works, with one build note per
package family. This file is only the working rules.

## Layout

- `packaging/<package>/` holds `build.sh` and the `debian/` tree it builds from. `debian/` there is the source of
  truth: every build copies it into a work tree under `~/.cache/<name>-dl/`, and that copy is never edited.
- `repos/small-gear-lab/conf/` is reprepro's configuration. The generated `db/`, `dists/` and `pool/` are not kept.

## Building

- Every `build.sh` takes `--help` (the comment at its top). Read it before running a script you have not used: a
  few take positional arguments (a version, a revision), so an unknown option is read as one of those.
- `build.sh build` starts from a fresh work tree. **Add `--no-clean` when the binaries do not have to be rebuilt**:
  a change to `debian/control`, `debian/changelog` or other metadata only. It keeps the work tree of the last build
  (and its compiled objects), copies `debian/` in again and builds, which takes seconds instead of a full compile.
  For the Rust packages that is the difference between minutes and a few seconds.
- Do not use `--no-clean` when the source, a patch, the compiler flags or `debian/rules` changed: build fresh.
  Where a package is built in a work tree that is always kept (`mozc`) or has nothing to compile (the fonts
  packages, `kitty-slang-compiler`), the option is accepted and does nothing.
- Keep the log of a long build: `./build.sh build 2>&1 | tee ~/.cache/<name>-dl/log-<what>.txt`. The scripts do
  not write one themselves.

## Releasing a package

1. Bump the revision in `debian/changelog` (`<upstream>-1~smallgearlab<N>`, suite `resolute`) and say what changed.
2. Build, then look at the result with `dpkg-deb -f <deb> Version Depends ...`.
3. Add the debs with `sgl-reprepro includedeb <suite> <debs>`. The suite (`resolute-testing` or `resolute`) is
   named in the header of the package's `build.sh`.

## Before anything leaves this machine

- Run `scripts/check-publishable.sh`. Nothing private goes into the tree: write paths as `~/...` or `$HOME/...`,
  never the absolute home directory.
- Commit messages say what changed. No `Co-Authored-By` or other attribution trailers.
