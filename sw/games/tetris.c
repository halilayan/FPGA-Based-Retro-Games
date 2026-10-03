/*
 * tetris.c -- see tetris.h.
 *
 * Tetromino shape table and rotation formula are reused from a well-known
 * public-domain-style reference implementation; everything else (board
 * storage, locking, line-clear, rendering, test hooks) is written from
 * scratch for this project's own conventions.
 *
 * gfx_get_pixel() always reads back 0 on real hardware, so it's never used
 * to recall what was under the falling piece. board[][] is this game's own
 * tracked truth; board_cell_color() reads it, never the frame buffer.
 */
#include "tetris.h"
#include "gfx.h"
#include "kbd.h"
#include "sys.h"
#include "pal.h"

#define BOARD_COLS 10
#define BOARD_ROWS 20
#define CELL       10

#define PF_X0 60   /* playfield left edge   - spans x=60..159 */
#define PF_Y0 24   /* playfield top edge    - spans y=24..223 */

#define NEXT_X0 230  /* NEXT preview box, 4x4 cells - spans x=230..269 */
#define NEXT_Y0 60   /*                               spans y=60..99  */
#define NEXT_LABEL_X (NEXT_X0 + (4 * CELL - 4 * 8) / 2)  /* centre "NEXT" (4 chars * 8px) over the box */
#define NEXT_LABEL_Y (NEXT_Y0 - 14)

#define SPAWN_X ((BOARD_COLS - 4) / 2)
#define SPAWN_Y 0

#define TICK_START 36  /* frames per row at game start (~0.6s @ 60fps) */
#define TICK_MIN   10  /* fastest gravity ever gets (soft drop via K_DOWN is separate, always 1) */

#define PAL_BG       0    /* black */
#define PAL_BORDER   255  /* white */
#define PAL_TITLE    250  /* cyan */
#define PAL_FRAME    180  /* steel blue-gray */
#define PAL_PIECE_I  40   /* cyan - classic Tetris piece colours */
#define PAL_PIECE_O  70   /* yellow */
#define PAL_PIECE_S  95   /* green */
#define PAL_PIECE_Z  120  /* red */
#define PAL_PIECE_T  145  /* purple */
#define PAL_PIECE_L  170  /* orange */
#define PAL_PIECE_J  210  /* blue */

/* uint8_t instead of the original's int, to save memory (112 vs 448 bytes). */
static const uint8_t tetrominoes[7][16] = {
    {0,0,0,0, 1,1,1,1, 0,0,0,0, 0,0,0,0},  /* I */
    {0,0,0,0, 0,1,1,0, 0,1,1,0, 0,0,0,0},  /* O */
    {0,0,0,0, 0,0,1,1, 0,1,1,0, 0,0,0,0},  /* S */
    {0,0,0,0, 1,1,0,0, 0,1,1,0, 0,0,0,0},  /* Z */
    {0,0,0,0, 0,1,0,0, 1,1,1,0, 0,0,0,0},  /* T */
    {0,0,0,0, 1,0,0,0, 1,1,1,0, 0,0,0,0},  /* L */
    {0,0,0,0, 0,0,0,1, 0,1,1,1, 0,0,0,0}   /* J */
};

/* piece index (0..6) -> its locked-cell / falling-cell palette colour. */
static const uint8_t piece_pal[7] = {
    PAL_PIECE_I, PAL_PIECE_O, PAL_PIECE_S, PAL_PIECE_Z, PAL_PIECE_T, PAL_PIECE_L, PAL_PIECE_J
};

/* board[row][col]: 0 = empty, else piece index + 1; locked blocks keep
 * their original piece's colour. */
static uint8_t board[BOARD_ROWS][BOARD_COLS];

static int cur_piece, cur_rot, cur_x, cur_y;
static int next_piece;

static int tick_counter;
static int tick_interval;

static uint32_t score;
static int game_over;

/* Dirty-rect drawing state, only written inside tetris_draw(): it always
 * recomputes the piece's position fresh from cur_x/cur_y/cur_rot/board[][]
 * rather than trusting a stale snapshot from update(). */
static int drawn_piece_valid;
static int drawn_row[4], drawn_col[4];

/* Set when a lock writes cells and/or a line clear shifts the board;
 * consumed by tetris_draw(). A line clear's full redraw supersedes the
 * lock redraw. */
static int dirty_lock;
static int lock_row[4], lock_col[4];
static int dirty_lines_cleared;

static int drawn_next_piece;
static uint32_t drawn_score;

/* Maps 4x4-local cell (x,y) at `rotation` to its flat index into
 * tetrominoes[piece][16] - reference formula, reused as-is. */
static int rotate_index(int x, int y, int rotation)
{
    switch (rotation % 4) {
    case 0: return x + y * 4;
    case 1: return 12 + y - (x * 4);
    case 2: return 15 - (y * 4) - x;
    case 3: return 3 - y + (x * 4);
    default: return 0;
    }
}

/* Collects the (row,col) of the piece's 4 set cells at board offset
 * (ox,oy), rotation `rot` - always returns exactly 4 for these shapes. */
static void piece_cells(int piece, int rot, int ox, int oy, int *rows, int *cols)
{
    int n = 0;
    for (int ly = 0; ly < 4; ly++) {
        for (int lx = 0; lx < 4; lx++) {
            if (tetrominoes[piece][rotate_index(lx, ly, rot)]) {
                rows[n] = oy + ly;
                cols[n] = ox + lx;
                n++;
            }
        }
    }
}

/* True iff every one of the piece's cells at this placement is both
 * in-bounds and over an empty board cell. */
static int valid(int piece, int rot, int ox, int oy)
{
    for (int ly = 0; ly < 4; ly++) {
        for (int lx = 0; lx < 4; lx++) {
            if (!tetrominoes[piece][rotate_index(lx, ly, rot)]) {
                continue;
            }
            int bx = ox + lx;
            int by = oy + ly;
            if (bx < 0 || bx >= BOARD_COLS || by < 0 || by >= BOARD_ROWS) {
                return 0;
            }
            if (board[by][bx]) {
                return 0;
            }
        }
    }
    return 1;
}

/* The board's own true colour at (row,col); 0 maps to background. Used
 * for erasing/redrawing the falling piece's trail. */
static uint8_t board_cell_color(int row, int col)
{
    uint8_t id = board[row][col];
    return id ? piece_pal[id - 1] : PAL_BG;
}

static void draw_board_cell(int row, int col)
{
    gfx_fill_rect(PF_X0 + col * CELL, PF_Y0 + row * CELL, CELL, CELL, board_cell_color(row, col));
}

static void draw_piece_cell(int row, int col, int piece)
{
    gfx_fill_rect(PF_X0 + col * CELL, PF_Y0 + row * CELL, CELL, CELL, piece_pal[piece]);
}

static void draw_next_preview(void)
{
    gfx_fill_rect(NEXT_X0, NEXT_Y0, 4 * CELL, 4 * CELL, PAL_BG);
    int rows[4], cols[4];
    piece_cells(next_piece, 0, 0, 0, rows, cols);
    for (int i = 0; i < 4; i++) {
        gfx_fill_rect(NEXT_X0 + cols[i] * CELL, NEXT_Y0 + rows[i] * CELL, CELL, CELL, piece_pal[next_piece]);
    }
}

/* Bottom-up full-row scan + shift-down clear. Re-checks the same row
 * index after a shift, since a row slid into a cleared slot may itself be
 * full. Returns the number of rows cleared (0 if none). */
static int clear_lines(void)
{
    int cleared = 0;
    for (int row = BOARD_ROWS - 1; row >= 0; row--) {
        int full = 1;
        for (int col = 0; col < BOARD_COLS; col++) {
            if (!board[row][col]) { full = 0; break; }
        }
        if (!full) {
            continue;
        }
        for (int r = row; r > 0; r--) {
            for (int col = 0; col < BOARD_COLS; col++) {
                board[r][col] = board[r - 1][col];
            }
        }
        for (int col = 0; col < BOARD_COLS; col++) {
            board[0][col] = 0;
        }
        cleared++;
        row++;  /* re-check this same row index - a shifted-down row may also be full */
    }
    return cleared;
}

/* Promotes next_piece to cur_piece, picks a new next_piece, and spawns at
 * top-centre; sets game_over if the spawn spot is already blocked. */
static void spawn_piece(void)
{
    cur_piece = next_piece;
    next_piece = (int)(sys_rng() % 7u);
    cur_rot = 0;
    cur_x = SPAWN_X;
    cur_y = SPAWN_Y;
    if (!valid(cur_piece, cur_rot, cur_x, cur_y)) {
        game_over = 1;
    }
}

/* Writes the falling piece into board[][], clears completed rows, and
 * spawns the next piece. dirty_lock records where the piece actually
 * landed, since hard drop can advance cur_y past where it was last
 * drawn. */
static void lock_piece(void)
{
    piece_cells(cur_piece, cur_rot, cur_x, cur_y, lock_row, lock_col);
    for (int i = 0; i < 4; i++) {
        board[lock_row[i]][lock_col[i]] = (uint8_t)(cur_piece + 1);
    }
    dirty_lock = 1;

    int cleared = clear_lines();
    if (cleared > 0) {
        score += 100u * (uint32_t)cleared * (uint32_t)cleared;
        dirty_lines_cleared = 1;
        tick_interval = TICK_START - (int)(score / 500u);
        if (tick_interval < TICK_MIN) { tick_interval = TICK_MIN; }
    }

    spawn_piece();
}

static void draw_hud(void)
{
    char buf[24];
    sys_format(buf, sizeof buf, "SKOR: %lu", (unsigned long)score);
    gfx_fill_rect(FB_W / 2 - 88, 4, 176, 8, PAL_BG);
    gfx_text_center(4, buf, PAL_TITLE);
}

void tetris_init(void)
{
    for (int row = 0; row < BOARD_ROWS; row++) {
        for (int col = 0; col < BOARD_COLS; col++) {
            board[row][col] = 0;
        }
    }

    score = 0;
    game_over = 0;
    tick_counter = 0;
    tick_interval = TICK_START;
    dirty_lock = 0;
    dirty_lines_cleared = 0;

    next_piece = (int)(sys_rng() % 7u);
    spawn_piece();  /* places the first piece, picks the first NEXT preview */

    pal_set_color(PAL_BG,     0x0, 0x0, 0x0);
    pal_set_color(PAL_BORDER, 0xF, 0xF, 0xF);
    pal_set_color(PAL_TITLE,  0x2, 0xD, 0xE);
    pal_set_color(PAL_FRAME,  0x7, 0x9, 0xC);
    {
        static const uint8_t piece_rgb[7][3] = {
            { 0x2, 0xE, 0xF }, /* I: cyan   */
            { 0xF, 0xF, 0x2 }, /* O: yellow */
            { 0x2, 0xE, 0x2 }, /* S: green  */
            { 0xE, 0x1, 0x1 }, /* Z: red    */
            { 0xA, 0x2, 0xE }, /* T: purple */
            { 0xF, 0x7, 0x0 }, /* L: orange */
            { 0x2, 0x4, 0xE }, /* J: blue   */
        };
        for (int p = 0; p < 7; p++) {
            pal_set_color(piece_pal[p], piece_rgb[p][0], piece_rgb[p][1], piece_rgb[p][2]);
        }
    }

    gfx_clear(PAL_BG);
    gfx_rect(0, 0, FB_W, FB_H, PAL_BORDER);
    gfx_rect(PF_X0 - 2, PF_Y0 - 2, BOARD_COLS * CELL + 4, BOARD_ROWS * CELL + 4, PAL_FRAME);
    gfx_rect(NEXT_X0 - 2, NEXT_Y0 - 2, 4 * CELL + 4, 4 * CELL + 4, PAL_FRAME);
    gfx_text(NEXT_LABEL_X, NEXT_LABEL_Y, "NEXT", PAL_TITLE);

    int rows[4], cols[4];
    piece_cells(cur_piece, cur_rot, cur_x, cur_y, rows, cols);
    for (int i = 0; i < 4; i++) {
        draw_piece_cell(rows[i], cols[i], cur_piece);
        drawn_row[i] = rows[i];
        drawn_col[i] = cols[i];
    }
    drawn_piece_valid = 1;

    draw_next_preview();
    drawn_next_piece = next_piece;

    drawn_score = score;
    draw_hud();
}

void tetris_update(void)
{
    if (game_over) {
        return;
    }

    if (kbd_hit(K_LEFT) && valid(cur_piece, cur_rot, cur_x - 1, cur_y)) {
        cur_x--;
    }
    if (kbd_hit(K_RIGHT) && valid(cur_piece, cur_rot, cur_x + 1, cur_y)) {
        cur_x++;
    }
    if (kbd_hit(K_UP)) {
        int new_rot = (cur_rot + 1) & 3;
        if (valid(cur_piece, new_rot, cur_x, cur_y)) {
            cur_rot = new_rot;
        }
    }
    if (kbd_hit(K_START)) {
        while (valid(cur_piece, cur_rot, cur_x, cur_y + 1)) {
            cur_y++;
        }
        lock_piece();
        tick_counter = 0;
        return;
    }

    tick_counter++;
    int interval = kbd_down(K_DOWN) ? 1 : tick_interval;
    if (tick_counter < interval) {
        return;
    }
    tick_counter = 0;

    if (valid(cur_piece, cur_rot, cur_x, cur_y + 1)) {
        cur_y++;
    } else {
        lock_piece();
    }
}

/*
 * Render order matters:
 *   1) erase wherever the piece was last drawn
 *   2) a line clear redraws the whole board (supersedes a lock redraw)
 *   3) otherwise a lock without a clear redraws just its 4 cells (hard
 *      drop can land several rows past the last-drawn position)
 *   4) draw the live falling piece on top, unless the game just ended
 *   5) NEXT preview / HUD, only when changed
 */
void tetris_draw(void)
{
    if (drawn_piece_valid) {
        for (int i = 0; i < 4; i++) {
            draw_board_cell(drawn_row[i], drawn_col[i]);
        }
    }

    if (dirty_lines_cleared) {
        for (int row = 0; row < BOARD_ROWS; row++) {
            for (int col = 0; col < BOARD_COLS; col++) {
                draw_board_cell(row, col);
            }
        }
        dirty_lines_cleared = 0;
        dirty_lock = 0;
    } else if (dirty_lock) {
        for (int i = 0; i < 4; i++) {
            draw_board_cell(lock_row[i], lock_col[i]);
        }
        dirty_lock = 0;
    }

    if (!game_over) {
        int rows[4], cols[4];
        piece_cells(cur_piece, cur_rot, cur_x, cur_y, rows, cols);
        for (int i = 0; i < 4; i++) {
            draw_piece_cell(rows[i], cols[i], cur_piece);
            drawn_row[i] = rows[i];
            drawn_col[i] = cols[i];
        }
        drawn_piece_valid = 1;
    } else {
        drawn_piece_valid = 0;
    }

    if (next_piece != drawn_next_piece) {
        draw_next_preview();
        drawn_next_piece = next_piece;
    }

    if (score != drawn_score) {
        draw_hud();
        drawn_score = score;
    }
}

uint32_t tetris_score(void) { return score; }
int      tetris_finished(void) { return game_over; }

int tetris_debug_piece(void) { return cur_piece; }
int tetris_debug_rot(void)   { return cur_rot; }
int tetris_debug_x(void)     { return cur_x; }
int tetris_debug_y(void)     { return cur_y; }
int tetris_debug_next_piece(void)    { return next_piece; }
int tetris_debug_tick_interval(void) { return tick_interval; }

void tetris_debug_set_piece(int piece, int rot, int x, int y)
{
    cur_piece = piece;
    cur_rot = rot;
    cur_x = x;
    cur_y = y;
    tick_counter = 0;
}

void tetris_debug_set_next_piece(int piece)
{
    next_piece = piece;
}

uint8_t tetris_debug_cell(int row, int col)
{
    return board[row][col];
}

void tetris_debug_set_cell(int row, int col, uint8_t color_id)
{
    board[row][col] = color_id;
}
