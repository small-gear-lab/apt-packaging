# neovide: the patched source build

`packaging/neovide/build-patched.sh` builds Neovide from the tagged source with a small patch series and
packages it as `neovide`. It is registered in **`resolute-testing`** (opt-in, `NotAutomatic` +
`ButAutomaticUpgrades`), next to the repack of the official binary in `resolute` (`build.sh`).

```sh
packaging/neovide/build-patched.sh 0.17.2 5      # -> neovide_0.17.2-1~smallgearlab5_amd64.deb
sgl-reprepro includedeb resolute-testing ~/.cache/nvim-dl/neovide/patched-0.17.2/out/neovide_*.deb
sudo apt install neovide/resolute-testing        # or: sudo dpkg -i the .deb
```

The number after `~smallgearlab` has to go up with every build (the repack in `resolute` is `~smallgearlab1`).
Once a testing version is installed, `ButAutomaticUpgrades` lets `apt upgrade` follow later testing builds.

## What the patches do

`packaging/neovide/patches/` (written against 0.17.2; applied in order):

| Patch | Change |
|---|---|
| 0001 | `--reuse-instance`, `--new-window` and `--chdir` work on Linux (they were macOS only): several windows in one process, one Neovim per window |
| 0002 | Make the OpenGL context current before drawing, flushing, swapping and resizing each window (with several windows every window but the last drew into the wrong context) |
| 0003 | `neovide.cycle_window` notification: focus the next or previous window |
| 0004 | `neovide.open_window` notification: open a window in a directory |
| 0005 | `neovide.focus_route` notification and `g:neovide_route_id`: focus a chosen window |
| 0006 | `neovide.open_window` takes extra arguments for the new Neovim (`--cmd`, `-c`) |
| 0007 | Terminate the shared EGL display only when the last window's renderer is dropped (closing one of several windows used to crash the whole process with a segfault in `memmove`) |
| 0008 | Draw the git branch symbols U+F5D0..U+F5FB natively (lines, curves, joints, commit circles). The set was designed for vim-flog and is also drawn by kitty. The shapes are written from the layout of the symbols, not copied from any implementation |
| 0009 | Draw images over the area of a Neovim window: `neovide.image_set` (window handle + options map) and `neovide.image_clear`. PNG, JPEG, WebP, GIF, BMP and ICO are decoded with the `image` crate (its codec features are enabled in `Cargo.toml`) and drawn with Skia, with mipmaps when shrinking. Modes for comparing two images: `single`, `difference` (`Difference` blend with a gain), `blend` and `swipe`. Each rendered window remembers its Neovim window handle |

`packaging/neovide/winit-patches/` patches winit 0.30.13, which the build copies from the cargo registry and points
to through `[patch.crates-io]`:

| Patch | Change |
|---|---|
| 0001 | Wayland: send the serial of the latest key press, and the surface that had the keyboard focus, with the xdg-activation token. Without them GNOME only shows a "window is ready" notification instead of moving the focus |

## Notes

- The Rust toolchain is the nightly pinned by the source's `rust-toolchain.toml` (rustup installs it on first use,
  about 700 MB under `~/.rustup`). Cargo downloads the crates and skia's prebuilt binaries during the build.
- The build is not `--locked`: pointing winit at a path changes its entry in `Cargo.lock`, and patch 0009 enables more
  codecs of the `image` crate (new crates come into `Cargo.lock`). The versions of the other crates stay as locked.
- Run long builds as a background task with a waiter on the `rc=` line of the log, so the end is noticed.
- Not sent upstream. A GitHub fork or a pull request needs the owner's permission and a look at Neovide's
  contribution policy first.
