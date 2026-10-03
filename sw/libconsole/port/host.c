/*
 * port/host.c -- kbd.h PC host port.
 *
 * No real keyboard capture here: kbd_poll() just commits whatever
 * kbd_feed_byte() has already been given (by sw/test, or a future
 * interactive PC driver).
 */
#include "kbd.h"
#include "gfx.h"
#include "sys.h"
#include "joystick.h"
#include "pal.h"
#include <stdio.h>

static uint8_t host_fb[FB_W * FB_H];

static uint8_t host_pal_r[256], host_pal_g[256], host_pal_b[256];

void pal_set_color(uint8_t idx, uint8_t r, uint8_t g, uint8_t b)
{
    host_pal_r[idx] = r & 0xFu;
    host_pal_g[idx] = g & 0xFu;
    host_pal_b[idx] = b & 0xFu;
}

void pal_get_color(uint8_t idx, uint8_t *r, uint8_t *g, uint8_t *b)
{
    *r = host_pal_r[idx];
    *g = host_pal_g[idx];
    *b = host_pal_b[idx];
}

void gfx_init(void)
{
    g_fb = host_fb;
}

void sys_write_str(const char *s)
{
    fputs(s, stdout);
}

void sys_wait_vblank(void)
{
    /* No real VBLANK on a PC - host tests/tools just run every frame back to back. */
}

/*
 * gfx_clear/gfx_fill_rect/gfx_sprite/gfx_sprite_key -- host.c's own
 * unaccelerated CPU-loop copies (hw.c's versions differ; see gfx.h).
 */
void gfx_clear(uint8_t color)
{
    gfx_fill_rect(0, 0, FB_W, FB_H, color);
}

void gfx_fill_rect(int x, int y, int w, int h, uint8_t color)
{
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            gfx_pixel(x + i, y + j, color);
        }
    }
}

void gfx_sprite(int x, int y, const uint8_t *data, int w, int h)
{
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            gfx_pixel(x + i, y + j, data[(uint32_t)j * w + i]);
        }
    }
}

void gfx_sprite_key(int x, int y, const uint8_t *data, int w, int h, uint8_t key_color)
{
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            uint8_t c = data[(uint32_t)j * w + i];
            if (c != key_color) {
                gfx_pixel(x + i, y + j, c);
            }
        }
    }
}

const uint8_t *gfx_load_asset(int offset, const uint8_t *data, int size)
{
    (void)offset;
    (void)size;
    return data; /* no separate asset memory on a PC - draw straight from the original array */
}

/* No real joystick on a PC - sw/test calls joystick_read() directly with
 * made-up ADC values instead, see joystick.h. */
void joystick_init(void) { }
void joystick_poll(void) { }

void kbd_init(void)
{
    kbd_reset_state();
}

void kbd_poll(void)
{
    kbd_commit_frame();
}
