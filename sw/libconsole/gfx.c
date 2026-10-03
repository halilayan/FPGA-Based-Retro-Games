/*
 * gfx.c -- shared drawing algorithms for gfx.h.
 *
 * Every routine here bottoms out in gfx_pixel(), so clipping only needs
 * to be correct in one place. gfx_clear/gfx_fill_rect/gfx_sprite/
 * gfx_sprite_key are port-specific (see port/hw.c, port/host.c).
 */
#include "gfx.h"
#include "font8x8.h"

volatile uint8_t *g_fb;

void gfx_pixel(int x, int y, uint8_t color)
{
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) {
        return;
    }
    g_fb[(uint32_t)y * FB_W + (uint32_t)x] = color;
}

uint8_t gfx_get_pixel(int x, int y)
{
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) {
        return 0;
    }
    return g_fb[(uint32_t)y * FB_W + (uint32_t)x];
}

void gfx_rect(int x, int y, int w, int h, uint8_t color)
{
    if (w <= 0 || h <= 0) {
        return;
    }
    for (int i = 0; i < w; i++) {
        gfx_pixel(x + i, y, color);
        gfx_pixel(x + i, y + h - 1, color);
    }
    for (int j = 0; j < h; j++) {
        gfx_pixel(x, y + j, color);
        gfx_pixel(x + w - 1, y + j, color);
    }
}

/* Bresenham, integer-only - no float or libm dependency. */
void gfx_line(int x0, int y0, int x1, int y1, uint8_t color)
{
    int dx = (x1 > x0) ? (x1 - x0) : (x0 - x1);
    int sx = (x0 < x1) ? 1 : -1;
    int dy = (y1 > y0) ? (y0 - y1) : (y1 - y0); /* negative abs(dy) */
    int sy = (y0 < y1) ? 1 : -1;
    int err = dx + dy;

    for (;;) {
        gfx_pixel(x0, y0, color);
        if (x0 == x1 && y0 == y1) {
            break;
        }
        int e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x0 += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y0 += sy;
        }
    }
}

/* Midpoint circle algorithm, 8-way symmetry, outline only. */
void gfx_circle(int cx, int cy, int r, uint8_t color)
{
    int x = r;
    int y = 0;
    int err = 1 - r;

    while (x >= y) {
        gfx_pixel(cx + x, cy + y, color);
        gfx_pixel(cx + y, cy + x, color);
        gfx_pixel(cx - y, cy + x, color);
        gfx_pixel(cx - x, cy + y, color);
        gfx_pixel(cx - x, cy - y, color);
        gfx_pixel(cx - y, cy - x, color);
        gfx_pixel(cx + y, cy - x, color);
        gfx_pixel(cx + x, cy - y, color);

        y++;
        if (err < 0) {
            err += 2 * y + 1;
        } else {
            x--;
            err += 2 * (y - x) + 1;
        }
    }
}

void gfx_read_rect(int x, int y, int w, int h, uint8_t *dst)
{
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            dst[(uint32_t)j * w + i] = gfx_get_pixel(x + i, y + j);
        }
    }
}

void gfx_write_rect(int x, int y, int w, int h, const uint8_t *src)
{
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            gfx_pixel(x + i, y + j, src[(uint32_t)j * w + i]);
        }
    }
}

void gfx_char(int x, int y, char c, uint8_t color)
{
    uint8_t code = (uint8_t)c;
    if (code < FONT8X8_FIRST || code > FONT8X8_LAST) {
        code = ' ';
    }
    const uint8_t *glyph = FONT8X8[code - FONT8X8_FIRST];
    for (int row = 0; row < 8; row++) {
        uint8_t bits = glyph[row];
        for (int col = 0; col < 8; col++) {
            if (bits & (0x80u >> col)) {
                gfx_pixel(x + col, y + row, color);
            }
        }
    }
}

void gfx_text(int x, int y, const char *s, uint8_t color)
{
    int cx = x;
    while (*s != '\0') {
        gfx_char(cx, y, *s, color);
        cx += 8;
        s++;
    }
}

void gfx_text_center(int y, const char *s, uint8_t color)
{
    int len = 0;
    for (const char *p = s; *p != '\0'; p++) {
        len++;
    }
    int x = (FB_W - len * 8) / 2;
    gfx_text(x, y, s, color);
}
