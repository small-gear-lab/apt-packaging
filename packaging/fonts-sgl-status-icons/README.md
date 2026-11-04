# fonts-sgl-status-icons

The font "SGL Status Icons" for kitty's `sgl__program_status_symbol` (see `../../docs/kitty-build.md`, patch 0019).

| Codepoint | Name | Use |
|---|---|---|
| U+E900 | idle_pause | idle (filled circle, pause bars cut out) |
| U+E901 | idle_moon | idle, alternative (moon and z) |
| U+E902 | blocked_hand | blocked (filled hand) |

- Drawings: `src/*.svg` (100x100, black). `outline/` is the same with strokes turned into outlines (fontforge ignores strokes).
- `./build.sh [--regen] [version] [revision]` builds the deb into `~/.cache/fonts-sgl-status-icons-build/`; register it with
  `sgl-reprepro includedeb resolute <deb>`.
- To add a glyph: draw `src/x.svg`, add a line to `GLYPHS` in `build-font.py`, run `./build.sh --regen <next version>`.
- Metrics must stay equal to Symbols Nerd Font Mono (upm 2048, ascent 1638, descent 410, advance 2048). kitty scales a
  symbol_map font by its own metrics; other values draw the glyphs smaller and lower. See `build-font.py`.
- A running kitty keeps the old font file in memory. After changing or upgrading the font, restart kitty (a config reload is not enough).
