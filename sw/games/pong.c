/*
 * pong.c -- see pong.h.
 */
#include "pong.h"
#include "gfx.h"
#include "kbd.h"
#include "sys.h"
#include "pal.h"

#define PADDLE_W 6
#define PADDLE_H 40
#define BALL_SIZE 6
#define PLAYER_X 10
#define AI_X (FB_W - 10 - PADDLE_W)
#define PLAYER_SPEED 3
#define AI_SPEED 2
#define WIN_SCORE 5

#define PAL_BG     0    /* black */
#define PAL_BORDER 255  /* white */
#define PAL_MID    64   /* dim gray centre-line dashes */
#define PAL_PADDLE 192  /* white, same as border/ball/title */
#define PAL_BALL   255
#define PAL_TITLE  255

static int player_y, ai_y;
static int ball_x, ball_y, ball_vx, ball_vy;
static uint32_t player_score, ai_score;

/*
 * Dirty-rect drawing state: the border/centre line/background are drawn
 * once by pong_init(); pong_draw() only erases each moving object's old
 * position and draws the new one, to avoid full-screen redraw tearing.
 * The ball needs save/restore since it can cross the centre line/border.
 */
static int prev_player_y, prev_ai_y;
static int prev_ball_x, prev_ball_y;
static uint8_t ball_under[BALL_SIZE * BALL_SIZE];
static int ball_under_valid;

/*
 * gfx_get_pixel() always reads back 0 on real hardware (no CPU read path
 * into the frame buffer), so the background under a moving object can't
 * be saved by reading it back. Instead, compute what the static
 * background layer must be at a given pixel from the same fixed rules
 * pong_init() used to draw it.
 */
static uint8_t static_bg_color_at(int x, int y)
{
    if (x < 0 || x >= FB_W || y < 0 || y >= FB_H) {
        return PAL_BG;
    }
    if (x == 0 || x == FB_W - 1 || y == 0 || y == FB_H - 1) {
        return PAL_BORDER;
    }
    if (x >= FB_W / 2 - 1 && x < FB_W / 2 - 1 + 2) {
        int rel = y - 4;
        if (rel >= 0 && (rel % 12) < 6) {
            return PAL_MID;
        }
    }
    return PAL_BG;
}

static void save_bg_under(int x, int y, int w, int h, uint8_t *dst)
{
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            dst[(uint32_t)j * w + i] = static_bg_color_at(x + i, y + j);
        }
    }
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
    ball_x = FB_W / 2 - BALL_SIZE / 2;
    ball_y = FB_H / 2 - BALL_SIZE / 2;
    ball_vx = (sys_rng() & 1u) ? 2 : -2;
    ball_vy = (sys_rng() & 1u) ? 2 : -2;
}

static void draw_score(void)
{
    char buf[16];
    sys_format(buf, sizeof buf, "%u - %u", (unsigned)player_score, (unsigned)ai_score);
    /* gfx_char() only sets pixels, never clears old ones underneath, so
     * the score area must be erased before redrawing or old digits bleed
     * through. erase_bg_rect() is used instead of a flat fill so the
     * centre-line dash it overlaps isn't blanked out. */
    erase_bg_rect(FB_W / 2 - 32, 4, 64, 8);
    gfx_text_center(4, buf, PAL_TITLE);
}

void pong_init(void)
{
    player_y = FB_H / 2 - PADDLE_H / 2;
    ai_y     = FB_H / 2 - PADDLE_H / 2;
    player_score = 0;
    ai_score     = 0;
    reset_ball();

    pal_set_color(PAL_BG,     0x0, 0x0, 0x0);
    pal_set_color(PAL_BORDER, 0xF, 0xF, 0xF);
    pal_set_color(PAL_MID,    0x6, 0x6, 0x6);
    pal_set_color(PAL_PADDLE, 0xF, 0xF, 0xF);

    gfx_clear(PAL_BG);
    gfx_rect(0, 0, FB_W, FB_H, PAL_BORDER);
    for (int y = 4; y < FB_H - 4; y += 12) {
        gfx_fill_rect(FB_W / 2 - 1, y, 2, 6, PAL_MID);
    }
    gfx_fill_rect(PLAYER_X, player_y, PADDLE_W, PADDLE_H, PAL_PADDLE);
    gfx_fill_rect(AI_X, ai_y, PADDLE_W, PADDLE_H, PAL_PADDLE);
    draw_score();

    prev_player_y = player_y;
    prev_ai_y = ai_y;
    ball_under_valid = 0;
}

void pong_update(void)
{
    if (kbd_down(K_UP))   { player_y -= PLAYER_SPEED; }
    if (kbd_down(K_DOWN)) { player_y += PLAYER_SPEED; }
    if (player_y < 0) { player_y = 0; }
    if (player_y + PADDLE_H > FB_H) { player_y = FB_H - PADDLE_H; }

    /* AI: chase the ball's vertical centre, one fixed step per frame. */
    int ai_center = ai_y + PADDLE_H / 2;
    int ball_center = ball_y + BALL_SIZE / 2;
    if (ai_center < ball_center - 2) { ai_y += AI_SPEED; }
    else if (ai_center > ball_center + 2) { ai_y -= AI_SPEED; }
    if (ai_y < 0) { ai_y = 0; }
    if (ai_y + PADDLE_H > FB_H) { ai_y = FB_H - PADDLE_H; }

    ball_x += ball_vx;
    ball_y += ball_vy;

    if (ball_y <= 0) { ball_y = 0; ball_vy = -ball_vy; }
    if (ball_y + BALL_SIZE >= FB_H) { ball_y = FB_H - BALL_SIZE; ball_vy = -ball_vy; }

    /* Player paddle (left side): hit position sets the return angle - a
     * real skill mechanic, since the human player chooses where on the
     * paddle to make contact. */
    if (ball_vx < 0 &&
        ball_x <= PLAYER_X + PADDLE_W && ball_x + BALL_SIZE >= PLAYER_X &&
        ball_y + BALL_SIZE >= player_y && ball_y <= player_y + PADDLE_H) {
        ball_x = PLAYER_X + PADDLE_W;
        ball_vx = -ball_vx;
        int offset = (ball_y + BALL_SIZE / 2) - (player_y + PADDLE_H / 2);
        ball_vy = offset / 6;
        if (ball_vy == 0) { ball_vy = 1; }
    }

    /* AI paddle (right side): the player's hit-offset formula would
     * degenerate here since the AI re-centres on the ball every frame, so
     * the return angle is randomized instead. */
    if (ball_vx > 0 &&
        ball_x + BALL_SIZE >= AI_X && ball_x <= AI_X + PADDLE_W &&
        ball_y + BALL_SIZE >= ai_y && ball_y <= ai_y + PADDLE_H) {
        ball_x = AI_X - BALL_SIZE;
        ball_vx = -ball_vx;
        ball_vy = (int)(sys_rng() % 5u) - 2; /* -2..2 */
        if (ball_vy == 0) { ball_vy = (sys_rng() & 1u) ? 1 : -1; }
    }

    if (ball_x + BALL_SIZE < 0) {
        ai_score++;
        reset_ball();
    } else if (ball_x > FB_W) {
        player_score++;
        reset_ball();
    }
}

void pong_draw(void)
{
    /* player_y/ai_y are clamped to [0, FB_H-PADDLE_H], so a paddle pinned
     * at the top/bottom wall sits with one row on the border; erase must
     * use erase_bg_rect() (true static background) rather than a flat
     * fill, or that stretch of border gets wiped permanently. */
    if (player_y != prev_player_y) {
        erase_bg_rect(PLAYER_X, prev_player_y, PADDLE_W, PADDLE_H);
        gfx_fill_rect(PLAYER_X, player_y, PADDLE_W, PADDLE_H, PAL_PADDLE);
        prev_player_y = player_y;
    }

    if (ai_y != prev_ai_y) {
        erase_bg_rect(AI_X, prev_ai_y, PADDLE_W, PADDLE_H);
        gfx_fill_rect(AI_X, ai_y, PADDLE_W, PADDLE_H, PAL_PADDLE);
        prev_ai_y = ai_y;
    }

    /* Restore what was under the ball's old spot, then save what's under
     * its new spot before drawing over it. save_bg_under/gfx_write_rect
     * clip per-pixel, so partially off-screen positions are safe. */
    if (ball_under_valid) {
        gfx_write_rect(prev_ball_x, prev_ball_y, BALL_SIZE, BALL_SIZE, ball_under);
    }
    save_bg_under(ball_x, ball_y, BALL_SIZE, BALL_SIZE, ball_under);
    gfx_fill_rect(ball_x, ball_y, BALL_SIZE, BALL_SIZE, PAL_BALL);
    prev_ball_x = ball_x;
    prev_ball_y = ball_y;
    ball_under_valid = 1;

    draw_score();
}

uint32_t pong_score(void)
{
    return player_score;
}

int pong_finished(void)
{
    return (player_score >= WIN_SCORE) || (ai_score >= WIN_SCORE);
}

int pong_debug_player_y(void) { return player_y; }
int pong_debug_ai_y(void)     { return ai_y; }
int pong_debug_ball_x(void)   { return ball_x; }
int pong_debug_ball_y(void)   { return ball_y; }
int pong_debug_ball_vx(void)  { return ball_vx; }
int pong_debug_ball_vy(void)  { return ball_vy; }

void pong_debug_set_ball(int x, int y, int vx, int vy)
{
    ball_x = x;
    ball_y = y;
    ball_vx = vx;
    ball_vy = vy;
}
