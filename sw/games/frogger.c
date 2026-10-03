/*
 * frogger.c -- see frogger.h.
 *
 * Rows, top (0) to bottom (12): 1 goal row -> 4 river lanes -> 1 grass row
 * -> 4 road lanes -> 2 grass rows -> 1 start row (see lane_type_of()).
 *
 * Every row has one flat background colour (lane_bg_color()); gfx_get_pixel()
 * always reads back 0 on real hardware, so rects are never read back to
 * save/restore. Cars/logs repaint their own rect every frame, which could
 * paint over a stationary frog - draw() redraws the frog's current cell
 * unconditionally, last, every frame, so it always ends up on top.
 *
 * Cars/logs are not grid-snapped (lane-local pixel x, wraps at GRID_W*CELL).
 * The frog stays grid-snapped, so riding a log doesn't carry it along - it
 * only survives as long as its cell happens to overlap a log.
 *
 * frog_prev_x/y is captured exactly once, at the top of frogger_update(),
 * before any hop/goal/collision logic runs - respawn_frog()/try_enter_goal()
 * only ever move frog_x/y, never frog_prev_x/y, so draw() always erases the
 * frog's correct last-drawn position even if a hop and a drown happen in
 * the same frame.
 */
#include "frogger.h"
#include "gfx.h"
#include "kbd.h"
#include "sys.h"
#include "pal.h"

#define CELL      16
#define GRID_X0   16
#define GRID_Y0   24
#define GRID_W    18
#define GRID_H    13
#define LANE_PX_W (GRID_W * CELL)  /* 288 - one full lane's wrap period */

#define GOAL_ROW      0
#define RIVER_ROW0    1
#define RIVER_LANES   4
#define GRASS_ROW_A   5
#define ROAD_ROW0     6
#define ROAD_LANES    4
#define GRASS_ROW_B   10
#define GRASS_ROW_C   11
#define START_ROW     12

#define START_X (GRID_W / 2)  /* column 9 */
#define START_Y START_ROW

#define OBJS_PER_LANE 2
#define CAR_W 32  /* 2 cells */
#define LOG_W 48  /* 3 cells */

#define HOME_SLOTS 4
#define HOME_SCORE 50

#define START_LIVES 3

#define PAL_BG          0    /* black */
#define PAL_BORDER    255    /* white */
#define PAL_TITLE     250    /* cyan */
#define PAL_GRASS      40    /* dark green */
#define PAL_ROAD       80    /* dark gray/asphalt */
#define PAL_RIVER     130    /* blue-ish water */
#define PAL_GOAL      170    /* green-ish */
#define PAL_HOME_EMPTY 150   /* muted tone - unfilled home slot */
#define PAL_HOME_FILLED 220  /* bright green-yellow - filled home slot */
#define PAL_FROG      240    /* bright green */
#define PAL_CAR        60    /* red */
#define PAL_LOG       190    /* brown */

enum { LANE_GOAL, LANE_RIVER, LANE_GRASS, LANE_ROAD };

static const int home_col[HOME_SLOTS] = { 2, 6, 11, 15 };

/* Cars and logs are the same kind of thing (a lane-local, wrapping rect),
 * handled through one shared "group" (0 = road/cars, 1 = river/logs)
 * instead of duplicating every advance/paint/collision loop. */
#define GROUP_ROAD  0
#define GROUP_RIVER 1
#define NUM_GROUPS  2
#define LANES_PER_GROUP 4  /* == ROAD_LANES == RIVER_LANES */

static const int group_row0[NUM_GROUPS] = { ROAD_ROW0, RIVER_ROW0 };
static const int group_width[NUM_GROUPS] = { CAR_W, LOG_W };
static const uint8_t group_color[NUM_GROUPS] = { PAL_CAR, PAL_LOG };

/* Alternating direction / varying speed per lane, for visual variety.
 * Sign = direction, magnitude = px/frame. */
static const int group_speed[NUM_GROUPS][LANES_PER_GROUP] = {
    {  1, -1,  2, -1 },  /* road/cars */
    { -1,  1, -1,  1 },  /* river/logs */
};

static int obj_x[NUM_GROUPS][LANES_PER_GROUP][OBJS_PER_LANE];
static int obj_prev_x[NUM_GROUPS][LANES_PER_GROUP][OBJS_PER_LANE];

static int frog_x, frog_y;
static int frog_prev_x, frog_prev_y;
static int dirty_frog_move;

static uint8_t home_filled[HOME_SLOTS];
static int homes_filled_count;
static int dirty_slot_fill;
static int dirty_slot_index;

static int lives;
static uint32_t score;
static int game_over;

static uint32_t drawn_score;
static int drawn_lives;

static int lane_type_of(int row)
{
    if (row == GOAL_ROW) { return LANE_GOAL; }
    if (row >= RIVER_ROW0 && row < RIVER_ROW0 + RIVER_LANES) { return LANE_RIVER; }
    if (row >= ROAD_ROW0 && row < ROAD_ROW0 + ROAD_LANES) { return LANE_ROAD; }
    return LANE_GRASS;  /* GRASS_ROW_A/B/C and START_ROW - all flat "safe" bg */
}

static uint8_t lane_bg_color(int row)
{
    switch (lane_type_of(row)) {
    case LANE_GOAL:  return PAL_GOAL;
    case LANE_RIVER: return PAL_RIVER;
    case LANE_ROAD:  return PAL_ROAD;
    default:         return PAL_GRASS;
    }
}

/* Keeps a lane-local x in [0, LANE_PX_W): scroll off one edge, reappear at
 * the other at the same lane/speed. */
static void advance_mover(int *x, int speed)
{
    *x += speed;
    if (*x < 0) { *x += LANE_PX_W; }
    else if (*x >= LANE_PX_W) { *x -= LANE_PX_W; }
}

/* Paints [lane_x, lane_x+w) at the given row, clipped to the grid's span,
 * plus a second copy shifted a full period left when the object pokes past
 * the right edge, so the wrap is seamless within the same frame. */
static void paint_span(int row, int lane_x, int w, uint8_t color)
{
    int y = GRID_Y0 + row * CELL;
    int x0 = GRID_X0 + lane_x;
    int x1 = x0 + w;
    if (x0 < GRID_X0) { x0 = GRID_X0; }
    if (x1 > GRID_X0 + LANE_PX_W) { x1 = GRID_X0 + LANE_PX_W; }
    if (x1 > x0) { gfx_fill_rect(x0, y, x1 - x0, CELL, color); }
}

static void paint_mover(int row, int lane_x, int w, uint8_t color)
{
    paint_span(row, lane_x, w, color);
    if (lane_x + w > LANE_PX_W) {
        paint_span(row, lane_x - LANE_PX_W, w, color);
    }
}

static int ranges_overlap(int a0, int a1, int b0, int b1)
{
    return a0 < b1 && b0 < a1;
}

static int mover_hits_col(int lane_x, int w, int frog_col)
{
    int f0 = frog_col * CELL;
    int f1 = f0 + CELL;
    if (ranges_overlap(lane_x, lane_x + w, f0, f1)) { return 1; }
    if (lane_x + w > LANE_PX_W &&
        ranges_overlap(lane_x - LANE_PX_W, lane_x - LANE_PX_W + w, f0, f1)) {
        return 1;
    }
    return 0;
}

static int group_overlaps(int g, int lane, int frog_col)
{
    for (int j = 0; j < OBJS_PER_LANE; j++) {
        if (mover_hits_col(obj_x[g][lane][j], group_width[g], frog_col)) { return 1; }
    }
    return 0;
}

/* frog_prev_x/y is captured once in frogger_update() (see header); this
 * function must only move frog_x/y, never touch frog_prev_x/y. */
static void respawn_frog(void)
{
    frog_x = START_X;
    frog_y = START_Y;
    dirty_frog_move = 1;
}

static void lose_life(void)
{
    if (lives > 0) { lives--; }
    if (lives == 0) {
        game_over = 1;  /* frog stays put at its death cell, like breakout's fallen ball */
    } else {
        respawn_frog();
    }
}

static int home_slot_at(int col)
{
    for (int i = 0; i < HOME_SLOTS; i++) {
        if (home_col[i] == col) { return i; }
    }
    return -1;
}

/* Handles a hop into the goal row: fills an empty slot (scores, respawns
 * the frog unless that was the last slot), or blocks the hop entirely
 * (already-filled slot, or any non-slot column). */
static void try_enter_goal(int col)
{
    int slot = home_slot_at(col);
    if (slot < 0 || home_filled[slot]) {
        return;  /* blocked: not a slot, or already filled */
    }

    home_filled[slot] = 1;
    homes_filled_count++;
    score += HOME_SCORE;
    dirty_slot_fill = 1;
    dirty_slot_index = slot;

    if (homes_filled_count == HOME_SLOTS) {
        game_over = 1;      /* win - frog stays sitting on the last slot */
        frog_x = col;
        frog_y = GOAL_ROW;
    } else {
        frog_x = START_X;   /* next frog starts over */
        frog_y = START_Y;
    }
    dirty_frog_move = 1;
}

static void draw_hud(void)
{
    char buf[32];
    sys_format(buf, sizeof buf, "SKOR: %lu   CAN: %lu", (unsigned long)score, (unsigned long)lives);
    gfx_fill_rect(FB_W / 2 - 88, 4, 176, 8, PAL_BG);
    gfx_text_center(4, buf, PAL_TITLE);
}

static void draw_frog_cell(int cx, int cy)
{
    int px = GRID_X0 + cx * CELL;
    int py = GRID_Y0 + cy * CELL;
    gfx_fill_rect(px, py, CELL, CELL, lane_bg_color(cy));
    gfx_fill_rect(px + 2, py + 2, CELL - 4, CELL - 4, PAL_FROG);
}

void frogger_init(void)
{
    lives = START_LIVES;
    score = 0;
    game_over = 0;
    homes_filled_count = 0;
    for (int i = 0; i < HOME_SLOTS; i++) { home_filled[i] = 0; }

    frog_x = START_X;
    frog_y = START_Y;
    dirty_frog_move = 0;
    dirty_slot_fill = 0;

    for (int g = 0; g < NUM_GROUPS; g++) {
        for (int i = 0; i < LANES_PER_GROUP; i++) {
            obj_x[g][i][0] = 0;
            obj_x[g][i][1] = LANE_PX_W / 2;
            obj_prev_x[g][i][0] = obj_x[g][i][0];
            obj_prev_x[g][i][1] = obj_x[g][i][1];
        }
    }

    pal_set_color(PAL_BG,          0x0, 0x0, 0x0);
    pal_set_color(PAL_BORDER,      0xF, 0xF, 0xF);
    pal_set_color(PAL_TITLE,       0x2, 0xD, 0xE);
    pal_set_color(PAL_GRASS,       0x0, 0x5, 0x0);
    pal_set_color(PAL_ROAD,        0x4, 0x4, 0x4);
    pal_set_color(PAL_RIVER,       0x3, 0x6, 0xA);
    pal_set_color(PAL_GOAL,        0x2, 0xA, 0x3);
    pal_set_color(PAL_HOME_EMPTY,  0x5, 0x5, 0x3);
    pal_set_color(PAL_HOME_FILLED, 0xA, 0xE, 0x4);
    pal_set_color(PAL_FROG,        0x6, 0xF, 0x2);
    pal_set_color(PAL_CAR,         0xE, 0x2, 0x1);
    pal_set_color(PAL_LOG,         0x8, 0x5, 0x1);

    gfx_clear(PAL_BG);
    gfx_rect(0, 0, FB_W, FB_H, PAL_BORDER);

    for (int row = 0; row < GRID_H; row++) {
        gfx_fill_rect(GRID_X0, GRID_Y0 + row * CELL, LANE_PX_W, CELL, lane_bg_color(row));
    }
    for (int i = 0; i < HOME_SLOTS; i++) {
        gfx_fill_rect(GRID_X0 + home_col[i] * CELL, GRID_Y0, CELL, CELL, PAL_HOME_EMPTY);
    }
    for (int g = 0; g < NUM_GROUPS; g++) {
        for (int i = 0; i < LANES_PER_GROUP; i++) {
            for (int j = 0; j < OBJS_PER_LANE; j++) {
                paint_mover(group_row0[g] + i, obj_x[g][i][j], group_width[g], group_color[g]);
            }
        }
    }

    draw_frog_cell(frog_x, frog_y);

    drawn_score = 0;
    drawn_lives = lives;
    draw_hud();
}

void frogger_update(void)
{
    if (game_over) {
        return;  /* freeze everything once the game has ended (win or loss) */
    }

    /* Captured exactly once, before any hop/goal/collision logic below
     * runs, so draw() always erases the frog's correct last-drawn position
     * even if a hop and a drown happen in the same call (see header). */
    frog_prev_x = frog_x;
    frog_prev_y = frog_y;

    for (int g = 0; g < NUM_GROUPS; g++) {
        for (int i = 0; i < LANES_PER_GROUP; i++) {
            for (int j = 0; j < OBJS_PER_LANE; j++) {
                advance_mover(&obj_x[g][i][j], group_speed[g][i]);
            }
        }
    }

    /* Discrete one-cell hop on the pressed edge only (kbd_hit, not
     * kbd_down). At most one hop per frame; priority UP>DOWN>LEFT>RIGHT. */
    int dx = 0, dy = 0, hop = 0;
    if (kbd_hit(K_UP))         { dy = -1; hop = 1; }
    else if (kbd_hit(K_DOWN))  { dy = 1;  hop = 1; }
    else if (kbd_hit(K_LEFT))  { dx = -1; hop = 1; }
    else if (kbd_hit(K_RIGHT)) { dx = 1;  hop = 1; }

    if (hop) {
        int nx = frog_x + dx;
        int ny = frog_y + dy;
        if (nx >= 0 && nx < GRID_W && ny >= 0 && ny < GRID_H) {
            if (ny == GOAL_ROW) {
                try_enter_goal(nx);
            } else {
                frog_x = nx;
                frog_y = ny;
                dirty_frog_move = 1;
            }
        }
    }

    /* Every-frame collision check (not just hop frames) - a car can drive
     * into a stationary frog, and a log can slide out from under one. */
    if (!game_over) {
        int t = lane_type_of(frog_y);
        if (t == LANE_ROAD) {
            if (group_overlaps(GROUP_ROAD, frog_y - ROAD_ROW0, frog_x)) { lose_life(); }
        } else if (t == LANE_RIVER) {
            if (!group_overlaps(GROUP_RIVER, frog_y - RIVER_ROW0, frog_x)) { lose_life(); }
        }
    }
}

void frogger_draw(void)
{
    if (dirty_frog_move) {
        gfx_fill_rect(GRID_X0 + frog_prev_x * CELL, GRID_Y0 + frog_prev_y * CELL,
                      CELL, CELL, lane_bg_color(frog_prev_y));
        dirty_frog_move = 0;
    }
    if (dirty_slot_fill) {
        int col = home_col[dirty_slot_index];
        gfx_fill_rect(GRID_X0 + col * CELL, GRID_Y0, CELL, CELL, PAL_HOME_FILLED);
        dirty_slot_fill = 0;
    }

    for (int g = 0; g < NUM_GROUPS; g++) {
        for (int i = 0; i < LANES_PER_GROUP; i++) {
            int row = group_row0[g] + i;
            for (int j = 0; j < OBJS_PER_LANE; j++) {
                paint_mover(row, obj_prev_x[g][i][j], group_width[g], lane_bg_color(row));
                paint_mover(row, obj_x[g][i][j], group_width[g], group_color[g]);
                obj_prev_x[g][i][j] = obj_x[g][i][j];
            }
        }
    }

    /* Always last, always unconditional - a passing car/log's own
     * erase+redraw can otherwise paint over a stationary frog. */
    draw_frog_cell(frog_x, frog_y);

    if (score != drawn_score || lives != drawn_lives) {
        draw_hud();
        drawn_score = score;
        drawn_lives = lives;
    }
}

uint32_t frogger_score(void) { return score; }
int      frogger_finished(void) { return game_over; }

int  frogger_debug_frog_x(void) { return frog_x; }
int  frogger_debug_frog_y(void) { return frog_y; }

void frogger_debug_set_frog(int x, int y)
{
    frog_x = x;
    frog_y = y;
    frog_prev_x = x;
    frog_prev_y = y;
    dirty_frog_move = 0;
}

int frogger_debug_lives(void) { return lives; }

void frogger_debug_set_car(int lane, int obj, int x)
{
    obj_x[GROUP_ROAD][lane][obj] = x;
    obj_prev_x[GROUP_ROAD][lane][obj] = x;
}

void frogger_debug_set_log(int lane, int obj, int x)
{
    obj_x[GROUP_RIVER][lane][obj] = x;
    obj_prev_x[GROUP_RIVER][lane][obj] = x;
}

int frogger_debug_car_x(int lane, int obj) { return obj_x[GROUP_ROAD][lane][obj]; }
int frogger_debug_log_x(int lane, int obj) { return obj_x[GROUP_RIVER][lane][obj]; }

int frogger_debug_home_filled(int slot) { return home_filled[slot]; }
int frogger_debug_homes_filled(void) { return homes_filled_count; }
