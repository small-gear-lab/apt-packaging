# neovim / neovide

Both are in `resolute` (normal suite). Installed 2026-11-10: neovim 0.12.6, neovide 0.17.2.

## neovim (`packaging/neovim/`)

Ubuntu's neovim 0.11.6-1 `debian/` carried over to a newer upstream. Differences: no test suite, no
`tree-sitter-*-src` build dependencies. The 0.12 runtime queries need newer grammars than those packages hold, so
`build.sh` fetches the grammars upstream pins in `cmake.deps/deps.txt` (sha256-checked) into `debian/external/ts/`
and `rules` compiles them with `$(CC)` (same layout as upstream's cmake.deps: every `src/*.c` is one module).

- Update: set the version at the top of `debian/changelog` (`<ver>-1~smallgearlab<N>`), `./build.sh <ver>`,
  then `sgl-reprepro includedeb resolute ~/.cache/nvim-dl/build/neovim*_<ver>-1~smallgearlab<N>_*.deb`.
- Source check: the commit id inside the GitHub tarball must equal the commit of the tag (`git get-tar-commit-id`;
  gzip gets SIGPIPE, hence `set +o pipefail` around it).
- Built against Ubuntu's libtree-sitter 0.25.9 and luv 1.51.0 (upstream bundles 0.26.13 / 1.52.1). It built and
  every grammar loads with its highlight query, but if something odd shows up in treesitter, look here first.
- `vim`/`vi` alternatives keep pointing at vim.basic (priority 30 is below vim's).
- Ubuntu's own security updates of neovim are not followed: 0.12.6-1~smallgearlab1 is newer than 0.11.6-1.

## neovide (`packaging/neovide/`)

Repack of the official `neovide-linux-x86_64.tar.gz` (sha256 digest from the GitHub API), plus the desktop entry,
icons and LICENSE from the source at the tag. `./build.sh <ver> <N>` then `includedeb`. Everything the binary
dlopen()s (libEGL, libGL, wayland-client/egl, xkbcommon(-x11), X11-xcb, Xcursor, Xi) is in Depends, not Recommends.
Licenses of the Rust crates inside the binary are not enumerated.

## tree-sitter-cli (`packaging/tree-sitter-cli/`)

Repack of the official `tree-sitter-linux-x64.gz` (digest from the GitHub API; license from the source at the tag).
Same package name as Ubuntu's (0.25.9-7), newer by version. Why: nvim-treesitter's main branch needs
tree-sitter-cli >= 0.26.1 to build parsers. Installed 2026-11-10: 0.27.2. `./build.sh <ver> <N>` then `includedeb`.
Parsers themselves are not packaged: nvim-treesitter compiles them into `~/.local/share/nvim/site/parser/`
(`:TSInstall`, `:TSUpdate`). Neovim's own bundled parsers (c lua vim vimdoc query markdown) live in /usr/lib/nvim/parser.
