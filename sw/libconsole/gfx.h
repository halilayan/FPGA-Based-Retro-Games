/*
 * gfx.h -- libconsole drawing API.
 *
 * Pixel/rect-outline/line/circle/text use identical CPU algorithms on
 * both ports (gfx.c). gfx_clear/gfx_fill_rect/gfx_sprite/gfx_sprite_key
 * are implemented per-port (hw.c/host.c): hw.c accelerates only
 * gfx_clear via the blitter - the other three use a plain CPU loop,
 * since blitter per-call overhead outweighs it for small, frequent draws.
 *
 * Not yet implemented: palette control, tile/scroll layers.
 */
#ifndef GFX_H
#define GFX_H

#include <stdint.h>

#define FB_W 320
#define FB_H 240

/*
 * Shared frame buffer pointer. Each port's gfx_init() sets this before any
 * drawing call: port/hw.c points it at the real FB_BASE, port/host.c points
 * it at a plain array. gfx.c is the only other file that touches it.
 */
extern volatile uint8_t *g_fb;

void gfx_init(void);  /* port-specific: hw.c points g_fb at FB_BASE, host.c allocates a buffer */

void gfx_clear(uint8_t color);
void gfx_pixel(int x, int y, uint8_t color);
void gfx_rect(int x, int y, int w, int h, uint8_t color);       /* outline only */
void gfx_fill_rect(int x, int y, int w, int h, uint8_t color);  /* filled */
void gfx_line(int x0, int y0, int x1, int y1, uint8_t color);
void gfx_circle(int cx, int cy, int r, uint8_t color);          /* outline only */
void gfx_sprite(int x, int y, const uint8_t *data, int w, int h); /* opaque blit, no key */
void gfx_sprite_key(int x, int y, const uint8_t *data, int w, int h, uint8_t key_color);

/*
 * Screen backup/restore for pause.c (row-major, w*h bytes). Note:
 * gfx_read_rect, like gfx_get_pixel, always reads back 0 on real
 * hardware - the AXI BRAM controller's read-data port is tied to a
 * constant, so framebuffer read-back only works on the host build.
 */
void gfx_read_rect(int x, int y, int w, int h, uint8_t *dst);
void gfx_write_rect(int x, int y, int w, int h, const uint8_t *src);

/*
 * Copies a compile-time sprite/tile array into asset memory (hw.c); on
 * host.c this is a no-op that hands back `data` unchanged. Call once at
 * load time, not per-frame.
 */
const uint8_t *gfx_load_asset(int offset, const uint8_t *data, int size);

void gfx_char(int x, int y, char c, uint8_t color);
void gfx_text(int x, int y, const char *s, uint8_t color);
void gfx_text_center(int y, const char *s, uint8_t color); /* centred on FB_W */

/* Test-only accessor. Always returns 0 on real hardware (see above). */
uint8_t gfx_get_pixel(int x, int y);

#endif
