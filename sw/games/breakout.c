/*
 * breakout.c -- see breakout.h.
 *
 * Bricks die one at a time, so the ball's trailing background isn't a
 * flat fill - it can be a still-alive brick, the border, or background.
 * gfx_get_pixel() always reads back 0 on real hardware, so
 * static_bg_color_at() below computes the background analytically from
 * brick_alive[][] instead of reading the frame buffer.
 */
#include "breakout.h"
#include "gfx.h"
#include "kbd.h"
#include "sys.h"
#include "pal.h"

#define PADDLE_W     32
#define PADDLE_H     6
#define PADDLE_Y     224
#define PADDLE_SPEED 4
#define BALL_SIZE    6

#define BRICK_COLS 10
#define BRICK_ROWS 5
#define BRICK_W    30
#define BRICK_H    8
#define BRICK_GAP  2
#define BRICK_X0   1   /* grid spans exactly [1, FB_W-1) - flush against the side borders, no overlap */
#define BRICK_Y0   20  /* a few px below the HUD text line */

#define START_LIVES 3

#define PAL_BG         0    /* black */
#define PAL_BORDER     255  /* white */
#define PAL_TITLE      250  /* bright cyan */
#define PAL_PADDLE     200  /* red */
#define PAL_BALL       230  /* white */
#define PAL_BRICK_BASE 40   /* brick row 0 (top); each row adds 8 (see brick_color()) -
                              * red/orange/yellow/gray/blue, one hue per row (kept
                              * deliberately muted, not a full rainbow spread) */

static int paddle_x;
static int ball_x, ball_y, ball_vx, ball_vy;
static uint8_t brick_alive[BRICK_ROWS][BRICK_COLS];
static int bricks_left;
static uint8_t lives;
static uint32_t score;
static int game_over;

/* Dirty-rect drawing state: prev_* positions are compared in draw(),
 * only the actual delta gets redrawn. */
static int prev_paddle_x;
static int prev_ball_x, prev_ball_y;
static int ball_valid;
static int dirty_brick_hit;
static int dirty_brick_row, dirty_brick_col;

static uint32_t drawn_score;
static uint8_t drawn_lives;

static uint8_t brick_color(int row)
{
    return (uint8_t)(PAL_BRICK_BASE + row * 8);
}

/* Maps a pixel to its brick's (row,col) if inside a brick's rect (not the
 * gap). Returns 0 otherwise; caller still checks brick_alive[][] itself. */
static int brick_cell_at(int x, int y, int *row_out, int *col_out)
{
    if (y < BRICK_Y0 || x < BRICK_X0) {
        return 0;
    }
    int row = (y - BRICK_Y0) / (BRICK_H + BRICK_GAP);
    int col = (x - BRICK_X0) / (BRICK_W + BRICK_GAP);
    if (row >= BRICK_ROWS || col >= BRICK_COLS) {
        return 0;
    }
    if ((y - BRICK_Y0) % (BRICK_H + BRICK_GAP) >= BRICK_H) {
        return 0;  /* vertical gap between rows */
    }
    if ((x - BRICK_X0) % (BRICK_W + BRICK_GAP) >= BRICK_W) {
        return 0;  /* horizontal gap between columns */
    }
    *row_out = row;
    *col_out = col;
    return 1;
}

static uint8_t static_bg_color_at(int x, int y)
{
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) {
        return PAL_BG;
    }
    if (x == 0 || x == FB_W - 1 || y == 0 || y == FB_H - 1) {
        return PAL_BORDER;
    }
    int row, col;
    if (brick_cell_at(x, y, &row, &col) && brick_alive[row][col]) {
        return brick_color(row);
    }
    return PAL_BG;
}

static void erase_bg_rect(int x, int y, int w, int h)
{
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            gfx_pixel(x + i, y + j, static_bg_color_at(x + i, y + j));
        }
    }
}

static void reset_ball(void)
{
    ball_x = paddle_x + PADDLE_W / 2 - BALL_SIZE / 2;
    ball_y = PADDLE_Y - BALL_SIZE - 4;
    ball_vx = (sys_rng() & 1u) ? 2 : -2;
    ball_vy = -2;
}

/* Shared by a real ball-vs-brick hit and the test-only debug mutator below,
 * so both paths keep bricks_left/finished() consistent. */
static void kill_brick(int row, int col)
{
    if (!brick_alive[row][col]) {
        return;
    }
    brick_alive[row][col] = 0;
    bricks_left--;
    if (bricks_left == 0) {
        game_over = 1;
    }
}

static void lose_life(void)
{
    if (lives > 0) {
        lives--;
    }
    if (lives == 0) {
        game_over = 1;
    } else {
        reset_ball();
    }
}

/* Simple AABB ball-vs-brick overlap check (no exact side detection).
 * Only one brick breaks per frame; stopping at the first hit keeps the
 * physics and the single dirty_brick_* slot simple. */
static void check_brick_collisions(void)
{
    if (ball_y >= BRICK_Y0 + BRICK_ROWS * (BRICK_H + BRICK_GAP)) {
        return;  /* ball is below the whole brick field - cheap early out */
    }
    for (int row = 0; row < BRICK_ROWS; row++) {
        int by = BRICK_Y0 + row * (BRICK_H + BRICK_GAP);
        if (ball_y + BALL_SIZE <= by || ball_y >= by + BRICK_H) {
            continue;
        }
        for (int col = 0; col < BRICK_COLS; col++) {
            if (!brick_alive[row][col]) {
                continue;
            }
            int bx = BRICK_X0 + col * (BRICK_W + BRICK_GAP);
            if (ball_x + BALL_SIZE <= bx || ball_x >= bx + BRICK_W) {
                continue;
            }
            score += (uint32_t)(row + 1) * 10;
            ball_vy = -ball_vy;
            dirty_brick_hit = 1;
            dirty_brick_row = row;
            dirty_brick_col = col;
            kill_brick(row, col);
            return;
        }
    }
}

static void draw_hud(void)
{
    char buf[32];
    sys_format(buf, sizeof buf, "SKOR: %lu   CAN: %lu", (unsigned long)score, (unsigned long)lives);
    gfx_fill_rect(FB_W / 2 - 88, 4, 176, 8, PAL_BG);
    gfx_text_center(4, buf, PAL_TITLE);
}

void breakout_init(void)
{
    paddle_x = FB_W / 2 - PADDLE_W / 2;
    lives = START_LIVES;
    score = 0;
    game_over = 0;
    bricks_left = BRICK_ROWS * BRICK_COLS;

    for (int row = 0; row < BRICK_ROWS; row++) {
        for (int col = 0; col < BRICK_COLS; col++) {
            brick_alive[row][col] = 1;
        }
    }

    reset_ball();

    pal_set_color(PAL_BG,     0x0, 0x0, 0x0);
    pal_set_color(PAL_BORDER, 0xF, 0xF, 0xF);
    pal_set_color(PAL_TITLE,  0x2, 0xD, 0xE);
    pal_set_color(PAL_PADDLE, 0xE, 0x1, 0x1);
    pal_set_color(PAL_BALL,   0xF, 0xF, 0xF);
    {
        static const uint8_t row_rgb[BRICK_ROWS][3] = {
            { 0xE, 0x1, 0x1 }, /* row 0: red    */
            { 0xF, 0x7, 0x0 }, /* row 1: orange */
            { 0xF, 0xE, 0x2 }, /* row 2: yellow */
            { 0x8, 0x8, 0x8 }, /* row 3: gray   */
            { 0x2, 0x4, 0xE }, /* row 4: blue   */
        };
        for (int row = 0; row < BRICK_ROWS; row++) {
            pal_set_color(brick_color(row), row_rgb[row][0], row_rgb[row][1], row_rgb[row][2]);
        }
    }

    gfx_clear(PAL_BG);
    gfx_rect(0, 0, FB_W, FB_H, PAL_BORDER);

    for (int row = 0; row < BRICK_ROWS; row++) {
        uint8_t color = brick_color(row);
        int by = BRICK_Y0 + row * (BRICK_H + BRICK_GAP);
        for (int col = 0; col < BRICK_COLS; col++) {
            int bx = BRICK_X0 + col * (BRICK_W + BRICK_GAP);
            gfx_fill_rect(bx, by, BRICK_W, BRICK_H, color);
        }
    }

    gfx_fill_rect(paddle_x, PADDLE_Y, PADDLE_W, PADDLE_H, PAL_PADDLE);
    gfx_fill_rect(ball_x, ball_y, BALL_SIZE, BALL_SIZE, PAL_BALL);

    prev_paddle_x = paddle_x;
    prev_ball_x = ball_x;
    prev_ball_y = ball_y;
    ball_valid = 1;
    dirty_brick_hit = 0;

    draw_hud();
    drawn_score = score;
    drawn_lives = lives;
}

void breakout_update(void)
{
    if (kbd_down(K_LEFT))  { paddle_x -= PADDLE_SPEED; }
    if (kbd_down(K_RIGHT)) { paddle_x += PADDLE_SPEED; }
    if (paddle_x < 1) { paddle_x = 1; }
    if (paddle_x + PADDLE_W > FB_W - 1) { paddle_x = FB_W - 1 - PADDLE_W; }

    ball_x += ball_vx;
    ball_y += ball_vy;

    if (ball_x <= 1) { ball_x = 1; ball_vx = -ball_vx; }
    if (ball_x + BALL_SIZE >= FB_W - 1) { ball_x = FB_W - 1 - BALL_SIZE; ball_vx = -ball_vx; }
    if (ball_y <= 1) { ball_y = 1; ball_vy = -ball_vy; }

    check_brick_collisions();

    /* Paddle bounce only when moving down into it; hit-offset sets the
     * return angle, clamped to never be exactly 0. */
    if (ball_vy > 0 &&
        ball_y + BALL_SIZE >= PADDLE_Y && ball_y <= PADDLE_Y + PADDLE_H &&
        ball_x + BALL_SIZE >= paddle_x && ball_x <= paddle_x + PADDLE_W) {
        ball_y = PADDLE_Y - BALL_SIZE;
        ball_vy = -ball_vy;
        int offset = (ball_x + BALL_SIZE / 2) - (paddle_x + PADDLE_W / 2);
        ball_vx = offset / 4;
        if (ball_vx == 0) { ball_vx = 1; }
    }

    /* No bottom wall bounce by design - falling past the paddle costs a life. */
    if (ball_y > FB_H - BALL_SIZE) {
        lose_life();
    }
}

void breakout_draw(void)
{
    if (dirty_brick_hit) {
        int bx = BRICK_X0 + dirty_brick_col * (BRICK_W + BRICK_GAP);
        int by = BRICK_Y0 + dirty_brick_row * (BRICK_H + BRICK_GAP);
        gfx_fill_rect(bx, by, BRICK_W, BRICK_H, PAL_BG);
        dirty_brick_hit = 0;
    }

    if (paddle_x != prev_paddle_x) {
        gfx_fill_rect(prev_paddle_x, PADDLE_Y, PADDLE_W, PADDLE_H, PAL_BG);
        gfx_fill_rect(paddle_x, PADDLE_Y, PADDLE_W, PADDLE_H, PAL_PADDLE);
        prev_paddle_x = paddle_x;
    }

    /* The ball moves almost every frame, so this erase/draw pair runs
     * unconditionally. */
    if (ball_valid) {
        erase_bg_rect(prev_ball_x, prev_ball_y, BALL_SIZE, BALL_SIZE);
    }
    gfx_fill_rect(ball_x, ball_y, BALL_SIZE, BALL_SIZE, PAL_BALL);
    prev_ball_x = ball_x;
    prev_ball_y = ball_y;
    ball_valid = 1;

    if (score != drawn_score || lives != drawn_lives) {
        draw_hud();
        drawn_score = score;
        drawn_lives = lives;
    }
}

uint32_t breakout_score(void) { return score; }
int      breakout_finished(void) { return game_over; }

int  breakout_debug_paddle_x(void) { return paddle_x; }
void breakout_debug_set_paddle_x(int x) { paddle_x = x; prev_paddle_x = x; }

int  breakout_debug_ball_x(void)  { return ball_x; }
int  breakout_debug_ball_y(void)  { return ball_y; }
int  breakout_debug_ball_vx(void) { return ball_vx; }
int  breakout_debug_ball_vy(void) { return ball_vy; }

void breakout_debug_set_ball(int x, int y, int vx, int vy)
{
    ball_x = x;
    ball_y = y;
    ball_vx = vx;
    ball_vy = vy;
}

int breakout_debug_lives(void) { return lives; }
int breakout_debug_bricks_left(void) { return bricks_left; }

int breakout_debug_brick_alive(int row, int col)
{
    return brick_alive[row][col];
}

void breakout_debug_kill_brick(int row, int col)
{
    kill_brick(row, col);
}
