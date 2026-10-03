/*
 * kernel.c -- see kernel.h for the state machine overview.
 *
 * States: BOOT -> MENU -> RUN -> PAUSE -> SCORE.
 */
#include <stddef.h>
#include "kernel.h"
#include "gfx.h"
#include "kbd.h"
#include "sys.h"
#include "joystick.h"
#include "gamelist.h"
#include "menu.h"
#include "pause.h"
#include "pal.h"

typedef enum { ST_BOOT, ST_MENU, ST_RUN, ST_PAUSE, ST_SCORE } state_t;

static state_t st;
static int sel;
static const game_t *g;

/* The palette is shared/persistent across games - a game that just ran
 * may have reassigned these same index numbers to its own colours, so
 * both screens below re-assert their own colours every time they draw. */
static void set_kernel_ui_colors(void)
{
    pal_set_color(0,   0x0, 0x0, 0x0); /* background - black */
    pal_set_color(255, 0xF, 0xF, 0xF); /* title/border - white */
    pal_set_color(192, 0x9, 0x9, 0x9); /* body text - mid gray */
    pal_set_color(128, 0x6, 0x6, 0x6); /* hint text - dim gray */
}

static void draw_boot_screen(void)
{
    set_kernel_ui_colors();
    gfx_clear(0);
    gfx_rect(0, 0, FB_W, FB_H, 255);
    gfx_text_center(FB_H / 2 - 8, "BASYS3 RETRO KONSOL", 255);
    gfx_text_center(FB_H / 2 + 8, "BASLAMAK ICIN BIR TUSA BASIN", 128);
}

static void draw_score_screen(void)
{
    char buf[24];
    sys_format(buf, sizeof buf, "SKOR: %lu", (unsigned long)g->score());

    set_kernel_ui_colors();
    gfx_clear(0);
    gfx_rect(0, 0, FB_W, FB_H, 255);
    gfx_text_center(FB_H / 2 - 16, "OYUN BITTI", 255);
    gfx_text_center(FB_H / 2, buf, 192);
    gfx_text_center(FB_H / 2 + 16, "DEVAM ICIN ENTER'A BASIN", 128);
}

void kernel_init(void)
{
    gfx_init();
    kbd_init();
    joystick_init();
    sys_init();

    st = ST_BOOT;
    sel = 0;
    g = NULL;

    draw_boot_screen();
}

void kernel_step(void)
{
    kbd_poll();
    sys_poll();

    switch (st) {
    case ST_BOOT:
        if (kbd_hit(K_START) || kbd_hit(K_UP) || kbd_hit(K_DOWN)) {
            st = ST_MENU;
            menu_draw(sel);
        }
        break;

    case ST_MENU: {
        int new_sel = menu_update(sel);
        if (new_sel != sel) {
            sel = new_sel;
            menu_draw(sel);
        }
        if (kbd_hit(K_START)) {
            g = &game_list[sel];
            g->init();
            st = ST_RUN;
        }
        break;
    }

    case ST_RUN:
        /* Esc is checked before update()/draw() so Resume doesn't skip
         * a tick ahead of the frame that was on screen when it was hit. */
        if (kbd_hit(K_ESC)) {
            pause_open(g);
            st = ST_PAUSE;
            break;
        }
        g->update();
        g->draw();
        if (g->finished()) {
            st = ST_SCORE;
            draw_score_screen();
        }
        break;

    case ST_PAUSE:
        switch (pause_update(g)) {
        case PAUSE_RESUME:
            pause_close();
            st = ST_RUN;
            break;
        case PAUSE_RESTART:
            pause_close();
            g->init();
            st = ST_RUN;
            break;
        case PAUSE_QUIT:
            pause_close();
            st = ST_SCORE;
            draw_score_screen();
            break;
        case PAUSE_NONE:
        default:
            break;
        }
        break;

    case ST_SCORE:
        if (kbd_hit(K_START)) {
            st = ST_MENU;
            menu_draw(sel);
        }
        break;
    }
}

int kernel_state(void)
{
    return (int)st;
}
