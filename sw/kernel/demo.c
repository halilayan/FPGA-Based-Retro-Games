/*
 * demo.c -- see demo.h. Transport-agnostic: only calls gfx_/kbd_/sys_.
 *
 * Color indices map to a fixed grayscale ramp set by palette_init.vhd,
 * not RGB - idx>>4 gives the gray level (0=black, 15=white).
 */
#include "demo.h"
#include "gfx.h"
#include "kbd.h"
#include "sys.h"

#define PAL_BG     0    /* gray level 0  - black */
#define PAL_BORDER 255  /* gray level 15 - white */
#define PAL_TITLE  192  /* gray level 12         */
#define PAL_BOX    128  /* gray level 8          */
#define PAL_DIM    64   /* gray level 4          */

#define BOX_SIZE   16
#define TOP_BAND   16   /* space reserved for the title row; the box never bounces into it */

static int box_x, box_y, box_vx, box_vy;

static const char *KEY_NAME[K_COUNT] = {
    "UP", "DN", "LT", "RT", "A", "B", "STA", "SEL", "ESC", "PAU"
};

void demo_init(void)
{
    gfx_init();
    kbd_init();
    sys_init();

    box_x = FB_W / 2 - BOX_SIZE / 2;
    box_y = FB_H / 2 - BOX_SIZE / 2;
    box_vx = 2;
    box_vy = 1;
}

static void draw_key_row(void)
{
    /* Held keys drawn bright, everything else dim. */
    int y = FB_H - 10;
    for (int k = 0; k < K_COUNT; k++) {
        uint8_t color = kbd_down(k) ? PAL_BORDER : PAL_DIM;
        gfx_text(k * 32 + 4, y, KEY_NAME[k], color);
    }
}

void demo_step(void)
{
    kbd_poll();
    sys_poll();

    if (kbd_down(K_LEFT))  { box_vx = -2; }
    if (kbd_down(K_RIGHT)) { box_vx = 2; }
    if (kbd_down(K_UP))    { box_vy = -2; }
    if (kbd_down(K_DOWN))  { box_vy = 2; }

    box_x += box_vx;
    box_y += box_vy;

    if (box_x < 0) { box_x = 0; box_vx = -box_vx; }
    if (box_x + BOX_SIZE > FB_W) { box_x = FB_W - BOX_SIZE; box_vx = -box_vx; }
    if (box_y < TOP_BAND) { box_y = TOP_BAND; box_vy = -box_vy; }
    if (box_y + BOX_SIZE > FB_H - 20) { box_y = FB_H - 20 - BOX_SIZE; box_vy = -box_vy; }

    gfx_clear(PAL_BG);
    gfx_rect(0, 0, FB_W, FB_H, PAL_BORDER);
    gfx_text_center(4, "BASYS3 RETRO KONSOL", PAL_TITLE);
    gfx_fill_rect(box_x, box_y, BOX_SIZE, BOX_SIZE, PAL_BOX);
    gfx_circle(box_x + BOX_SIZE / 2, box_y + BOX_SIZE / 2, BOX_SIZE, PAL_TITLE);
    draw_key_row();

    /* Periodic status line over UART. */
    if ((sys_ticks() % 60u) == 0u) {
        sys_log("demo: frame=%lu pad=0x%04X box=(%d,%d) rng=%lu\n",
                (unsigned long)sys_ticks(), (unsigned)kbd_pad_state(),
                box_x, box_y, (unsigned long)sys_rng());
    }
}
