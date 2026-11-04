# fontforge -lang=py -script build-font.py <outline dir> <output.ttf> <version>
# Builds the SGL Status Icons font. The glyphs are squares that fill the same box as Symbols Nerd Font Mono
# (upm 2048, ascent 1638, descent 410, advance 2048): kitty scales a symbol_map font by its own metrics, and a
# font with other metrics is drawn smaller and lower than the Nerd Font glyphs next to it.
import sys

import fontforge
import psMat

outline_dir, out, version = sys.argv[1:4]

GLYPH = 2048
ADV = 2048
ASCENT, DESCENT = 1638, 410
# codepoint, outline file, glyph name. U+E900-E9FF is not used by Nerd Fonts (see glyphnames.json).
GLYPHS = [
    (0xE900, 'e-pause-outline.svg', 'idle_pause'),
    (0xE901, 'b-moon-outline.svg', 'idle_moon'),
    (0xE902, 'h-hand-outline.svg', 'blocked_hand'),
]

f = fontforge.font()
f.encoding = 'UnicodeFull'
f.familyname = 'SGL Status Icons'
f.fontname = 'SGLStatusIcons-Regular'
f.fullname = 'SGL Status Icons Regular'
f.version = version
# em first, then ascent/descent (their sum is the em); do not set the hhea/OS2 values by hand, fontforge adds them
f.em = ASCENT + DESCENT
f.ascent = ASCENT
f.descent = DESCENT
f.copyright = 'Copyright (c) small-gear-lab. Glyphs drawn for personal use.'
for cp, svg, name in GLYPHS:
    g = f.createChar(cp, name)
    g.importOutlines(f'{outline_dir}/{svg}')
    g.removeOverlap()
    g.correctDirection()
    xmin, ymin, xmax, ymax = g.boundingBox()
    g.transform(psMat.scale(GLYPH / max(xmax - xmin, ymax - ymin)))
    xmin, ymin, xmax, ymax = g.boundingBox()
    # centre in the advance and in the box between descent and ascent
    g.transform(psMat.translate(ADV / 2 - (xmin + xmax) / 2, (ASCENT - DESCENT) / 2 - (ymin + ymax) / 2))
    g.width = ADV
    g.round()
f.generate(out)
