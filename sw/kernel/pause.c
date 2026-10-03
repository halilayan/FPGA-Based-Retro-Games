/*
 * pause.c -- see pause.h.
 *
 * Every path out of PAUSE calls pause_close() exactly once, keeping
 * pal_push_dimmed()/pal_pop() balanced across pause/resume/quit cycles.
 */
#include "pause.h"
#include "gfx.h"
#include "kbd.h"
#include "pal.h"
#include "sys.h"

#define BOX_X 80
#define BOX_Y 60
#define BOX_W 160
#define BOX_H 110
#define ITEM_X 92
#define ITEM_Y 92
#define ITEM_DY 14

#define COL_PANEL  64
#define COL_BORDER 255
#define COL_TITLE  255
#define COL_TEXT   192
#define COL_SEL    255
#define COL_CURSOR 255
#define COL_DIM    128
#define COL_WARN   255

enum { IT_RESUME, IT_RESTART, IT_CONTROLS, IT_QUIT, IT_COUNT };

static const char *ITEM_NAME[IT_COUNT] = {
    "DEVAM ET", "YENIDEN BASLAT", "KONTROLLER", "ANA MENUYE DON"
};

static int sel;
static int confirming;
static int showing_controls;
static uint8_t backup[BOX_W * BOX_H];

static void pause_draw(const game_t *g)
{
    gfx_fill_rect(BOX_X, BOX_Y, BOX_W, BOX_H, COL_PANEL);
    gfx_rect(BOX_X, BOX_Y, BOX_W, BOX_H, COL_BORDER);
    gfx_text_center(BOX_Y + 8, "DURAKLATILDI", COL_TITLE);

    if (showing_controls) {
        gfx_text(ITEM_X, ITEM_Y, g->controls, COL_TEXT);
        gfx_text(ITEM_X, BOX_Y + BOX_H - 16, "ESC = GERI", COL_DIM);
        return;
    }

    if (confirming) {
        gfx_text_center(ITEM_Y + 10, "EMIN MISINIZ?", COL_WARN);
        gfx_text_center(ITEM_Y + 26, "ENTER = EVET", COL_TEXT);
        gfx_text_center(ITEM_Y + 40, "ESC = HAYIR", COL_TEXT);
        return;
    }

    for (int i = 0; i < IT_COUNT; i++) {
        int y = ITEM_Y + i * ITEM_DY;
        gfx_text(ITEM_X - 10, y, (i == sel) ? ">" : " ", COL_CURSOR);
        gfx_text(ITEM_X, y, ITEM_NAME[i], (i == sel) ? COL_SEL : COL_TEXT);
    }

    char buf[24];
    sys_format(buf, sizeof buf, "SKOR: %lu", (unsigned long)g->score());
    gfx_text(ITEM_X, BOX_Y + BOX_H - 16, buf, COL_DIM);
}

void pause_open(const game_t *g)
{
    sel = IT_RESUME;
    confirming = 0;
    showing_controls = 0;

    /* Re-assert this screen's own colours every open - the palette is
     * shared/persistent, the game that was just running may have
     * reassigned these same indices. */
    pal_set_color(COL_PANEL,  0x3, 0x3, 0x3);
    pal_set_color(COL_BORDER, 0xF, 0xF, 0xF);
    pal_set_color(COL_TEXT,   0x9, 0x9, 0x9);
    pal_set_color(COL_DIM,    0x6, 0x6, 0x6);

    gfx_read_rect(BOX_X, BOX_Y, BOX_W, BOX_H, backup);
    pal_push_dimmed(50);
    pause_draw(g);
}

pause_result_t pause_update(const game_t *g)
{
    if (showing_controls) {
        if (kbd_hit(K_ESC)) { showing_controls = 0; pause_draw(g); }
        return PAUSE_NONE;
    }

    if (confirming) {
        if (kbd_hit(K_START)) {
            return (sel == IT_RESTART) ? PAUSE_RESTART : PAUSE_QUIT;
        }
        if (kbd_hit(K_ESC)) { confirming = 0; pause_draw(g); }
        return PAUSE_NONE;
    }

    if (kbd_hit(K_ESC)) { return PAUSE_RESUME; }

    if (kbd_hit(K_UP))   { sel = (sel + IT_COUNT - 1) % IT_COUNT; pause_draw(g); }
    if (kbd_hit(K_DOWN)) { sel = (sel + 1)            % IT_COUNT; pause_draw(g); }

    if (kbd_hit(K_START)) {
        switch (sel) {
        case IT_RESUME:
            return PAUSE_RESUME;
        case IT_CONTROLS:
            showing_controls = 1;
            pause_draw(g);
            break;
        case IT_RESTART:
        case IT_QUIT:
            confirming = 1;
            pause_draw(g);
            break;
        default:
            break;
        }
    }
    return PAUSE_NONE;
}

void pause_close(void)
{
    pal_pop();
    gfx_write_rect(BOX_X, BOX_Y, BOX_W, BOX_H, backup);
}
