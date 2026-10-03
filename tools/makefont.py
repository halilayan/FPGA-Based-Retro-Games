#!/usr/bin/env python3
"""
tools/makefont.py -- font8x8.h generator.

Current version: bootstraps sw/libconsole/font8x8.h by rendering the system's
DejaVu Sans Mono Bold TTF at 64px and thresholding it down to 8x8 per glyph -
there is no hand-drawn pixel-font sprite sheet yet.

Once custom pixel art exists: this script should switch to the classic
"font PNG sheet -> hex array" flow (the original G.1 design) - a mode that
reads a single PNG spritesheet with each character hand-drawn in an 8x8 cell
and writes the same font8x8.h format. The current TTF-based path is a usable
default until that art exists.

Output: sw/libconsole/font8x8.h (+ font_contact_sheet.png for visual review)
"""
from PIL import Image, ImageDraw, ImageFont

FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
RENDER = 64          # render cell size (px) before downsampling
CELL_W, CELL_H = 8, 8
FIRST, LAST = 32, 127  # printable ASCII, inclusive
THRESHOLD = 110

font = ImageFont.truetype(FONT_PATH, RENDER)
ascent, descent = font.getmetrics()
cell_h_px = ascent + descent
cell_w_px = font.getsize("M")[0]

glyphs = {}
for code in range(FIRST, LAST + 1):
    ch = chr(code)
    img = Image.new("L", (cell_w_px, cell_h_px), 0)
    d = ImageDraw.Draw(img)
    d.text((0, 0), ch, font=font, fill=255)
    small = img.resize((CELL_W, CELL_H), Image.BOX)
    bits = [[1 if small.getpixel((x, y)) >= THRESHOLD else 0 for x in range(CELL_W)]
            for y in range(CELL_H)]
    glyphs[code] = bits

# ---- C header ----
lines = []
lines.append("/*")
lines.append(" * font8x8.h -- 8x8 bitmap font, ASCII 32-127.")
lines.append(" *")
lines.append(" * Generated from DejaVu Sans Mono Bold (thresholded to 8x8 per glyph) - see")
lines.append(" * tools/makefont.py. Row N, bit 7 (MSB) = leftmost pixel, bit 0 = rightmost.")
lines.append(" * FONT8X8[c - 32] is the glyph for ASCII code c (space..DEL-1).")
lines.append(" */")
lines.append("#ifndef FONT8X8_H")
lines.append("#define FONT8X8_H")
lines.append("")
lines.append("#include <stdint.h>")
lines.append("")
lines.append(f"#define FONT8X8_FIRST {FIRST}")
lines.append(f"#define FONT8X8_LAST  {LAST}")
lines.append("")
lines.append(f"static const uint8_t FONT8X8[{LAST - FIRST + 1}][8] = {{")
for code in range(FIRST, LAST + 1):
    bits = glyphs[code]
    row_bytes = []
    for y in range(CELL_H):
        v = 0
        for x in range(CELL_W):
            v = (v << 1) | bits[y][x]
        row_bytes.append(f"0x{v:02X}")
    ch = chr(code)
    comment = ch if ch not in ("\\", "'", "/") else "\\" + ch
    lines.append("    { " + ", ".join(row_bytes) + " },  /* %3d '%s' */" % (code, comment))
lines.append("};")
lines.append("")
lines.append("#endif")

with open("../sw/libconsole/font8x8.h", "w") as f:
    f.write("\n".join(lines) + "\n")

# ---- contact sheet for visual verification ----
cols, rows = 16, (LAST - FIRST + 1 + 15) // 16
scale = 6
sheet = Image.new("L", (cols * CELL_W * scale, rows * CELL_H * scale), 0)
for i, code in enumerate(range(FIRST, LAST + 1)):
    cx, cy = (i % cols) * CELL_W * scale, (i // cols) * CELL_H * scale
    bits = glyphs[code]
    for y in range(CELL_H):
        for x in range(CELL_W):
            if bits[y][x]:
                for dy in range(scale):
                    for dx in range(scale):
                        sheet.putpixel((cx + x * scale + dx, cy + y * scale + dy), 255)
sheet.save("font_contact_sheet.png")  # left under tools/ for review
print("done: font8x8.h, font_contact_sheet.png")
