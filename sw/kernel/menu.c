/*
 * menu.c -- see menu.h.
 */
#include "menu.h"
#include "gamelist.h"
#include "gfx.h"
#include "kbd.h"
#include "pal.h"

#define COL_BG     0
#define COL_BORDER 255
#define COL_TITLE  255
#define COL_ITEM   192
#define COL_SEL    255
#define COL_CURSOR 255
#define COL_HINT   128

#define ITEM_X 56
#define ITEM_Y 60
#define ITEM_DY 16

int menu_update(int sel)
{
    if (kbd_hit(K_UP))   { sel = (sel + game_count - 1) % game_count; }
    if (kbd_hit(K_DOWN)) { sel = (sel + 1)               % game_count; }
    return sel;
}

void menu_draw(int sel)
{
    /* Re-assert this screen's own colours every draw - the palette is
     * shared/persistent, a game may have reassigned these same indices. */
    pal_set_color(COL_BG,     0x0, 0x0, 0x0);
    pal_set_color(COL_BORDER, 0xF, 0xF, 0xF);
    pal_set_color(COL_ITEM,   0x9, 0x9, 0x9);
    pal_set_color(COL_HINT,   0x6, 0x6, 0x6);

    gfx_clear(COL_BG);
    gfx_rect(0, 0, FB_W, FB_H, COL_BORDER);
    gfx_text_center(20, "BASYS3 RETRO KONSOL", COL_TITLE);

    for (int i = 0; i < game_count; i++) {
        int y = ITEM_Y + i * ITEM_DY;
        gfx_text(ITEM_X - 16, y, (i == sel) ? ">" : " ", COL_CURSOR);
        gfx_text(ITEM_X, y, game_list[i].name, (i == sel) ? COL_SEL : COL_ITEM);
    }

    gfx_text_center(FB_H - 16, "YON: SEC  ENTER: BASLA", COL_HINT);
}
