/*
 * flappy.c -- see flappy.h.
 *
 * The bird and pipes fly only over PAL_SKY, so a flat-fill erase is always
 * correct. gfx_get_pixel() always reads back 0 on real hardware, so it's
 * never used to save/restore what's under them.
 *
 * FLIGHT_BOTTOM is FB_H-2 (not FB_H-1), and fill_interior() clamps fills to
 * [1, FB_W-2]: pipes scroll across the full width and can go off-screen, so
 * without this margin an erase could overlap and permanently paint over
 * the border.
 */
#include "flappy.h"
#include "gfx.h"
#include "kbd.h"
#include "sys.h"
#include "pal.h"

#define FLIGHT_TOP    16        /* a few px below the HUD text line */
#define FLIGHT_BOTTOM (FB_H - 2) /* one row above the bottom border - see header comment */

#define BIRD_X     50   /* fixed horizontal position */
#define BIRD_SIZE  8    /* small square glyph, 8x8 */

#define PIPE_COUNT    2
#define PIPE_W        24
#define PIPE_SPACING  150  /* x distance between the two pipe-pairs' left edges */
#define PIPE_SPEED    2    /* px/frame, classic Flappy Bird scroll speed */
#define GAP_H         70   /* generous gap height (spec: ~60-70px) */
#define GAP_MARGIN    20   /* min px between a gap and the flight area's own top/bottom edge */

/*
 * Integer bird physics: GRAVITY is added to vy every frame the bird isn't
 * flapping, capped by FALL_CAP. FLAP_VY gives an instant upward kick,
 * left uncapped, so gravity naturally decelerates the climb into an arc.
 * FLAP_VY=-8 buys a ~36px arc, about half of GAP_H (70), tuned so a
 * well-timed flap crosses a gap without overshooting it.
 */
#define GRAVITY   1
#define FALL_CAP  5
#define FLAP_VY   (-8)

#define PAL_BG       0    /* black */
#define PAL_BORDER   255  /* white */
#define PAL_TITLE    250  /* bright cyan */
#define PAL_SKY      80   /* sky blue */
#define PAL_BIRD     230  /* yellow */
#define PAL_PIPE     150  /* green */
#define PAL_PIPE_CAP 170  /* lighter highlight-green rim band */

#define PIPE_CAP_H 6  /* height of the rim band drawn at each pipe's gap-facing end - cosmetic only */

/* 8x8 bird silhouette, row-major MSB-first (bit 0x80 = leftmost column).
 * Two frames for a wing-flap animation, toggled once per flap. */
static const uint8_t BIRD_GLYPH[2][8] = {
    { 0x38, 0x7C, 0xFE, 0xFF, 0xF7, 0xFE, 0x7C, 0x38 }, /* wing down */
    { 0x38, 0x7C, 0xF6, 0xFF, 0xFF, 0xFE, 0x7C, 0x38 }, /* wing up */
};

static int bird_y, bird_vy;
static int wing_frame;
static int dead;
static uint32_t score;

static int pipe_x[PIPE_COUNT];
static int pipe_gap_y0[PIPE_COUNT];   /* first open row of the gap */
static int pipe_scored[PIPE_COUNT];

/* Dirty-rect drawing state: draw() compares against these "last actually
 * drawn" values and only touches pixels that changed. */
static int drawn_bird_y;
static int drawn_pipe_x[PIPE_COUNT];
static int drawn_pipe_gap_y0[PIPE_COUNT];
static uint32_t drawn_score;

/* Test-only instrumentation: counts full-column vs per-slice pipe redraws
 * (see flappy_debug_full_redraw_count()/flappy_debug_slice_redraw_count()
 * in flappy.h). */
static uint32_t full_redraw_count;
static uint32_t slice_redraw_count;

/* Clamps a horizontal fill to the flight area's interior columns
 * [1, FB_W-2] before handing it to gfx_fill_rect() - pipes scroll across
 * the full width, into negative x and past FB_W, so this keeps them off
 * the border. */
static void fill_interior(int x, int y, int w, int h, uint8_t color)
{
    int x0 = x;
    int x1 = x + w;
    if (x0 < 1) { x0 = 1; }
    if (x1 > FB_W - 1) { x1 = FB_W - 1; }
    if (x0 >= x1 || h <= 0) {
        return;
    }
    gfx_fill_rect(x0, y, x1 - x0, h, color);
}

static int random_gap_y0(void)
{
    const int lo = FLIGHT_TOP + GAP_MARGIN;
    const int range = (FLIGHT_BOTTOM - GAP_MARGIN - GAP_H) - lo + 1;
    return lo + (int)(sys_rng() % (uint32_t)range);
}

static void draw_pipe(int i)
{
    int x = pipe_x[i];
    int gap0 = pipe_gap_y0[i];
    int top_h = gap0 - FLIGHT_TOP;
    int bot_y = gap0 + GAP_H;
    int bot_h = FLIGHT_BOTTOM - bot_y + 1;

    fill_interior(x, FLIGHT_TOP, PIPE_W, top_h, PAL_PIPE);
    fill_interior(x, bot_y, PIPE_W, bot_h, PAL_PIPE);

    /* Rim/cap band at each pipe's gap-facing end, drawn over the body
     * fill. Clamped to the stub's own height so a short stub never draws
     * a cap taller than itself (defensive; GAP_MARGIN keeps this from
     * normally happening). */
    int cap_h = (top_h < PIPE_CAP_H) ? top_h : PIPE_CAP_H;
    if (cap_h > 0) {
        fill_interior(x, gap0 - cap_h, PIPE_W, cap_h, PAL_PIPE_CAP);
    }
    cap_h = (bot_h < PIPE_CAP_H) ? bot_h : PIPE_CAP_H;
    if (cap_h > 0) {
        fill_interior(x, bot_y, PIPE_W, cap_h, PAL_PIPE_CAP);
    }
}

/* Erases the full vertical strip (gap included) at the pipe's last-drawn
 * x in one flat fill; repainting the already-sky gap is harmless. */
static void erase_pipe(int i)
{
    fill_interior(drawn_pipe_x[i], FLIGHT_TOP, PIPE_W, FLIGHT_BOTTOM - FLIGHT_TOP + 1, PAL_SKY);
}

/* Single-column (w=1) versions of draw_pipe()/erase_pipe()'s fills, used
 * by flappy_draw()'s scroll-step fast path: pipes move every frame, so a
 * full erase+redraw touches ~5,350 pixels per pipe per frame - enough to
 * overrun the VBLANK window on real hardware and cause visible tearing.
 * Touching only the columns that actually changed avoids this. */
static void draw_pipe_slice(int x, int gap0)
{
    int top_h = gap0 - FLIGHT_TOP;
    int bot_y = gap0 + GAP_H;
    int bot_h = FLIGHT_BOTTOM - bot_y + 1;

    fill_interior(x, FLIGHT_TOP, 1, top_h, PAL_PIPE);
    fill_interior(x, bot_y, 1, bot_h, PAL_PIPE);

    int cap_h = (top_h < PIPE_CAP_H) ? top_h : PIPE_CAP_H;
    if (cap_h > 0) {
        fill_interior(x, gap0 - cap_h, 1, cap_h, PAL_PIPE_CAP);
    }
    cap_h = (bot_h < PIPE_CAP_H) ? bot_h : PIPE_CAP_H;
    if (cap_h > 0) {
        fill_interior(x, bot_y, 1, cap_h, PAL_PIPE_CAP);
    }
}

static void erase_pipe_slice(int x)
{
    fill_interior(x, FLIGHT_TOP, 1, FLIGHT_BOTTOM - FLIGHT_TOP + 1, PAL_SKY);
}

static void draw_bird(void)
{
    const uint8_t *glyph = BIRD_GLYPH[wing_frame];
    for (int row = 0; row < 8; row++) {
        uint8_t bits = glyph[row];
        for (int col = 0; col < 8; col++) {
            if (bits & (0x80u >> col)) {
                gfx_pixel(BIRD_X + col, bird_y + row, PAL_BIRD);
            }
        }
    }
}

/* Flat PAL_SKY fill is correct here since nothing but sky is ever behind
 * the bird. */
static void erase_bird(void)
{
    gfx_fill_rect(BIRD_X, drawn_bird_y, BIRD_SIZE, BIRD_SIZE, PAL_SKY);
}

static void draw_hud(void)
{
    char buf[32];
    sys_format(buf, sizeof buf, "SKOR: %lu", (unsigned long)score);
    gfx_fill_rect(FB_W / 2 - 60, 4, 120, 8, PAL_BG);
    gfx_text_center(4, buf, PAL_TITLE);
}

void flappy_init(void)
{
    bird_y = FLIGHT_TOP + (FLIGHT_BOTTOM - FLIGHT_TOP + 1) / 2 - BIRD_SIZE / 2;
    bird_vy = 0;
    wing_frame = 0;
    dead = 0;
    score = 0;
    full_redraw_count = 0;
    slice_redraw_count = 0;

    /* First pipe-pair appears a bit after start; second spaced
     * PIPE_SPACING behind it, both off-screen to the right. */
    pipe_x[0] = FB_W + 40;
    pipe_gap_y0[0] = random_gap_y0();
    pipe_scored[0] = 0;

    pipe_x[1] = pipe_x[0] + PIPE_SPACING;
    pipe_gap_y0[1] = random_gap_y0();
    pipe_scored[1] = 0;

    pal_set_color(PAL_BG,       0x0, 0x0, 0x0);
    pal_set_color(PAL_BORDER,   0xF, 0xF, 0xF);
    pal_set_color(PAL_TITLE,    0x2, 0xD, 0xE);
    pal_set_color(PAL_SKY,      0x4, 0xA, 0xF);
    pal_set_color(PAL_BIRD,     0xF, 0xE, 0x2);
    pal_set_color(PAL_PIPE,     0x1, 0xB, 0x2);
    pal_set_color(PAL_PIPE_CAP, 0x4, 0xF, 0x4);

    gfx_clear(PAL_BG);
    gfx_rect(0, 0, FB_W, FB_H, PAL_BORDER);
    gfx_fill_rect(1, FLIGHT_TOP, FB_W - 2, FLIGHT_BOTTOM - FLIGHT_TOP + 1, PAL_SKY);

    for (int i = 0; i < PIPE_COUNT; i++) {
        draw_pipe(i);
        drawn_pipe_x[i] = pipe_x[i];
        drawn_pipe_gap_y0[i] = pipe_gap_y0[i];
    }

    draw_bird();
    drawn_bird_y = bird_y;

    draw_hud();
    drawn_score = score;
}

void flappy_update(void)
{
    if (dead) {
        return;
    }

    if (kbd_hit(K_A)) {
        bird_vy = FLAP_VY;
        wing_frame ^= 1;  /* toggle the wing-flap animation frame - see BIRD_GLYPH */
    } else {
        bird_vy += GRAVITY;
        if (bird_vy > FALL_CAP) { bird_vy = FALL_CAP; }
    }
    bird_y += bird_vy;

    if (bird_y < FLIGHT_TOP || bird_y + BIRD_SIZE - 1 > FLIGHT_BOTTOM) {
        dead = 1;
        return;
    }

    for (int i = 0; i < PIPE_COUNT; i++) {
        pipe_x[i] -= PIPE_SPEED;

        /* Scoring: the first frame this pipe-pair's trailing (right) edge
         * crosses the bird's fixed x, award one point, once. */
        if (!pipe_scored[i] && pipe_x[i] + PIPE_W <= BIRD_X) {
            score++;
            pipe_scored[i] = 1;
        }

        /* Recycle once past the left edge: reposition relative to the
         * other pipe-pair to keep spacing constant, fresh gap, reset
         * scored flag. */
        if (pipe_x[i] + PIPE_W <= 1) {
            int other = 1 - i;
            pipe_x[i] = pipe_x[other] + PIPE_SPACING;
            pipe_gap_y0[i] = random_gap_y0();
            pipe_scored[i] = 0;
        }

        /* Collision: only matters while this pipe-pair's x range overlaps
         * the bird's fixed x range at all. */
        if (BIRD_X + BIRD_SIZE > pipe_x[i] && BIRD_X < pipe_x[i] + PIPE_W) {
            if (bird_y < pipe_gap_y0[i] || bird_y + BIRD_SIZE > pipe_gap_y0[i] + GAP_H) {
                dead = 1;
            }
        }
    }
}

void flappy_draw(void)
{
    /* Pipes first, bird last, so the bird always ends up on top of
     * whatever the pipe step painted underneath it this frame. */
    for (int i = 0; i < PIPE_COUNT; i++) {
        int dx = drawn_pipe_x[i] - pipe_x[i]; /* > 0: moved left by dx since the last draw */

        if (pipe_gap_y0[i] != drawn_pipe_gap_y0[i]) {
            /* Gap changed (recycled, or first draw after init) - no
             * shortcut available. */
            full_redraw_count++;
            erase_pipe(i);
            draw_pipe(i);
        } else if (dx == PIPE_SPEED) {
            /* Ordinary scroll tick: only the PIPE_SPEED columns actually
             * exposed or newly covered need repainting. */
            slice_redraw_count++;
            for (int k = 0; k < PIPE_SPEED; k++) {
                erase_pipe_slice(drawn_pipe_x[i] + PIPE_W - 1 - k);
                draw_pipe_slice(pipe_x[i] + k, pipe_gap_y0[i]);
            }
        } else if (dx != 0) {
            /* Any other jump (e.g. a test's debug setter) - fall back to
             * the always-correct full redraw. */
            full_redraw_count++;
            erase_pipe(i);
            draw_pipe(i);
        }

        drawn_pipe_x[i] = pipe_x[i];
        drawn_pipe_gap_y0[i] = pipe_gap_y0[i];
    }

    if (bird_y != drawn_bird_y) {
        erase_bird();
        draw_bird();
        drawn_bird_y = bird_y;
    }

    if (score != drawn_score) {
        draw_hud();
        drawn_score = score;
    }
}

uint32_t flappy_score(void) { return score; }
int      flappy_finished(void) { return dead; }

int  flappy_debug_bird_y(void)  { return bird_y; }
int  flappy_debug_bird_vy(void) { return bird_vy; }

void flappy_debug_set_bird(int y, int vy)
{
    bird_y = y;
    bird_vy = vy;
}

int flappy_debug_pipe_x(int idx)      { return pipe_x[idx]; }
int flappy_debug_pipe_gap_y0(int idx) { return pipe_gap_y0[idx]; }
int flappy_debug_pipe_scored(int idx) { return pipe_scored[idx]; }

void flappy_debug_set_pipe(int idx, int x, int gap_y0)
{
    pipe_x[idx] = x;
    pipe_gap_y0[idx] = gap_y0;
    pipe_scored[idx] = 0;
}

uint32_t flappy_debug_full_redraw_count(void)  { return full_redraw_count; }
uint32_t flappy_debug_slice_redraw_count(void) { return slice_redraw_count; }
