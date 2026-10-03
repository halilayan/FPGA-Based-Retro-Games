/*
 * snake.c -- see snake.h.
 *
 * The play grid never overlaps the outer border, HUD text, or inner
 * frame, so a plain flat-colour erase is always correct (no background
 * save/restore needed, unlike pong.c's ball).
 */
#include "snake.h"
#include "gfx.h"
#include "kbd.h"
#include "sys.h"
#include "pal.h"

#define CELL     8
#define GRID_X0  8
#define GRID_Y0  16
#define GRID_W   38
#define GRID_H   27
#define MAX_LEN  (GRID_W * GRID_H)

#define PAL_BG      0    /* black */
#define PAL_BORDER  255  /* white */
#define PAL_TITLE   255
#define PAL_FRAME   180  /* steel blue-gray */
#define PAL_CELL_A  24   /* dark green checkerboard tile A */
#define PAL_CELL_B  32   /* dark green checkerboard tile B, a touch lighter */
#define PAL_HEAD    248  /* bright yellow-green */
#define PAL_BODY    176  /* green */
#define PAL_FOOD    120  /* blue */

/* Speed ramps with score: tick interval drops by 1 every
 * SPEEDUP_SCORE_STEP points, floored at TICK_MIN. */
#define TICK_START 12  /* frames per move at game start */
#define TICK_MIN   6   /* fastest the snake ever moves */
#define SPEEDUP_SCORE_STEP 60  /* every this many points, tick_interval drops by 1 */

enum { DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT };

/* Diamond glyph for food; same row-major MSB-first bit layout as font8x8.h. */
static const uint8_t FOOD_GLYPH[8] = {
    0x18, 0x3C, 0x7E, 0xFF, 0xFF, 0x7E, 0x3C, 0x18,
};

static uint8_t body_x[MAX_LEN];
static uint8_t body_y[MAX_LEN];
static int length;
static int dir;
static int next_dir;

static int food_x, food_y;

static int tick_counter;
static int tick_interval;

static uint32_t score;
static uint32_t best_score;
static int dead;

/* Set by snake_update() when a tick moves the snake; consumed and
 * cleared by snake_draw() after rendering the delta. */
static int dirty_move;
static int dirty_prev_head_x, dirty_prev_head_y;
static int dirty_new_head_x, dirty_new_head_y;
static int dirty_erase_tail;
static int dirty_erase_x, dirty_erase_y;
static int dirty_new_food;

static uint32_t drawn_score, drawn_best;

static uint8_t cell_bg_color(int cx, int cy)
{
    return ((cx + cy) & 1) ? PAL_CELL_B : PAL_CELL_A;
}

static void draw_head_cell(int cx, int cy)
{
    gfx_fill_rect(GRID_X0 + cx * CELL, GRID_Y0 + cy * CELL, CELL, CELL, PAL_HEAD);
}

static void draw_body_cell(int cx, int cy)
{
    int px = GRID_X0 + cx * CELL;
    int py = GRID_Y0 + cy * CELL;
    gfx_fill_rect(px, py, CELL, CELL, cell_bg_color(cx, cy));
    gfx_fill_rect(px + 1, py + 1, CELL - 2, CELL - 2, PAL_BODY);
}

static void erase_cell(int cx, int cy)
{
    gfx_fill_rect(GRID_X0 + cx * CELL, GRID_Y0 + cy * CELL, CELL, CELL, cell_bg_color(cx, cy));
}

static void draw_food_glyph(int cx, int cy)
{
    int px = GRID_X0 + cx * CELL;
    int py = GRID_Y0 + cy * CELL;
    uint8_t bg = cell_bg_color(cx, cy);
    for (int row = 0; row < 8; row++) {
        uint8_t bits = FOOD_GLYPH[row];
        for (int col = 0; col < 8; col++) {
            gfx_pixel(px + col, py + row, (bits & (0x80u >> col)) ? PAL_FOOD : bg);
        }
    }
}

static int cell_has_snake(int cx, int cy)
{
    for (int i = 0; i < length; i++) {
        if (body_x[i] == cx && body_y[i] == cy) {
            return 1;
        }
    }
    return 0;
}

/* Pick a random free cell, retry if it landed on the snake. Bounded
 * (not "while(1)") so a snake that has filled the grid can't hang the
 * system looking for a free cell that no longer exists. */
static int place_food(void)
{
    for (int attempt = 0; attempt < MAX_LEN; attempt++) {
        int cx = (int)(sys_rng() % (uint32_t)GRID_W);
        int cy = (int)(sys_rng() % (uint32_t)GRID_H);
        if (!cell_has_snake(cx, cy)) {
            food_x = cx;
            food_y = cy;
            return 1;
        }
    }
    return 0;  /* board is full - caller treats this as a win */
}

static void draw_hud(void)
{
    char buf[32];
    sys_format(buf, sizeof buf, "SKOR: %lu   REKOR: %lu", (unsigned long)score, (unsigned long)best_score);
    gfx_fill_rect(FB_W / 2 - 88, 4, 176, 8, PAL_BG);
    gfx_text_center(4, buf, PAL_TITLE);
}

void snake_init(void)
{
    length = 3;
    dir = DIR_RIGHT;
    next_dir = DIR_RIGHT;

    int start_x = GRID_W / 2;
    int start_y = GRID_H / 2;
    body_x[0] = (uint8_t)start_x;     body_y[0] = (uint8_t)start_y;
    body_x[1] = (uint8_t)(start_x - 1); body_y[1] = (uint8_t)start_y;
    body_x[2] = (uint8_t)(start_x - 2); body_y[2] = (uint8_t)start_y;

    tick_counter = 0;
    tick_interval = TICK_START;
    score = 0;
    dead = 0;
    dirty_move = 0;

    pal_set_color(PAL_BG,     0x0, 0x0, 0x0);
    pal_set_color(PAL_BORDER, 0xF, 0xF, 0xF);
    pal_set_color(PAL_FRAME,  0x7, 0x9, 0xC);
    pal_set_color(PAL_CELL_A, 0x0, 0x3, 0x0);
    pal_set_color(PAL_CELL_B, 0x0, 0x4, 0x0);
    pal_set_color(PAL_HEAD,   0xA, 0xF, 0x2);
    pal_set_color(PAL_BODY,   0x2, 0xB, 0x2);
    pal_set_color(PAL_FOOD,   0x2, 0x4, 0xE);

    gfx_clear(PAL_BG);
    gfx_rect(0, 0, FB_W, FB_H, PAL_BORDER);
    gfx_rect(GRID_X0 - 2, GRID_Y0 - 2, GRID_W * CELL + 4, GRID_H * CELL + 4, PAL_FRAME);

    for (int cy = 0; cy < GRID_H; cy++) {
        for (int cx = 0; cx < GRID_W; cx++) {
            gfx_fill_rect(GRID_X0 + cx * CELL, GRID_Y0 + cy * CELL, CELL, CELL, cell_bg_color(cx, cy));
        }
    }
    for (int i = 0; i < length; i++) {
        if (i == 0) { draw_head_cell(body_x[i], body_y[i]); }
        else        { draw_body_cell(body_x[i], body_y[i]); }
    }

    place_food();
    draw_food_glyph(food_x, food_y);

    drawn_score = 0;
    drawn_best = best_score;
    draw_hud();
}

void snake_update(void)
{
    if (kbd_hit(K_UP)    && dir != DIR_DOWN)  { next_dir = DIR_UP; }
    if (kbd_hit(K_DOWN)  && dir != DIR_UP)    { next_dir = DIR_DOWN; }
    if (kbd_hit(K_LEFT)  && dir != DIR_RIGHT) { next_dir = DIR_LEFT; }
    if (kbd_hit(K_RIGHT) && dir != DIR_LEFT)  { next_dir = DIR_RIGHT; }

    tick_counter++;
    if (tick_counter < tick_interval) {
        return;
    }
    tick_counter = 0;
    dir = next_dir;

    int new_x = body_x[0];
    int new_y = body_y[0];
    switch (dir) {
    case DIR_UP:    new_y--; break;
    case DIR_DOWN:  new_y++; break;
    case DIR_LEFT:  new_x--; break;
    case DIR_RIGHT: new_x++; break;
    }

    if (new_x < 0 || new_x >= GRID_W || new_y < 0 || new_y >= GRID_H || cell_has_snake(new_x, new_y)) {
        dead = 1;
        if (score > best_score) { best_score = score; }
        return;
    }

    int growing = (new_x == food_x && new_y == food_y);

    dirty_prev_head_x = body_x[0];
    dirty_prev_head_y = body_y[0];
    dirty_erase_tail = !growing;
    dirty_erase_x = body_x[length - 1];
    dirty_erase_y = body_y[length - 1];

    int shift_count = growing ? length : length - 1;
    for (int i = shift_count; i > 0; i--) {
        body_x[i] = body_x[i - 1];
        body_y[i] = body_y[i - 1];
    }
    if (growing) { length++; }
    body_x[0] = (uint8_t)new_x;
    body_y[0] = (uint8_t)new_y;

    dirty_new_head_x = new_x;
    dirty_new_head_y = new_y;
    dirty_move = 1;
    dirty_new_food = 0;

    if (growing) {
        score += 10;
        tick_interval = TICK_START - (int)(score / SPEEDUP_SCORE_STEP);
        if (tick_interval < TICK_MIN) { tick_interval = TICK_MIN; }
        if (!place_food()) {
            dead = 1;  /* board full - no room left for new food, treat as a win */
        } else {
            dirty_new_food = 1;
        }
    }
}

void snake_draw(void)
{
    if (dirty_move) {
        if (length > 1) { draw_body_cell(dirty_prev_head_x, dirty_prev_head_y); }
        draw_head_cell(dirty_new_head_x, dirty_new_head_y);
        if (dirty_erase_tail) { erase_cell(dirty_erase_x, dirty_erase_y); }
        if (dirty_new_food) { draw_food_glyph(food_x, food_y); }
        dirty_move = 0;
    }
    if (score != drawn_score || best_score != drawn_best) {
        draw_hud();
        drawn_score = score;
        drawn_best = best_score;
    }
}

uint32_t snake_score(void) { return score; }
int      snake_finished(void) { return dead; }

int snake_debug_head_x(void) { return body_x[0]; }
int snake_debug_head_y(void) { return body_y[0]; }
int snake_debug_length(void) { return length; }
int snake_debug_dir(void)    { return dir; }
int snake_debug_food_x(void) { return food_x; }
int snake_debug_food_y(void) { return food_y; }
int snake_debug_tick_interval(void) { return tick_interval; }

void snake_debug_force_body(const int *xs, const int *ys, int len, int new_dir)
{
    length = len;
    for (int i = 0; i < len; i++) {
        body_x[i] = (uint8_t)xs[i];
        body_y[i] = (uint8_t)ys[i];
    }
    dir = new_dir;
    next_dir = new_dir;
    tick_counter = tick_interval - 1;  /* next update() call ticks immediately */
}

void snake_debug_force_food(int x, int y)
{
    food_x = x;
    food_y = y;
}
