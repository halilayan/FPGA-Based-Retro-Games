/*
 * tetris.h -- Classic falling-block puzzle (10x20 board, 7 tetrominoes).
 * Tetromino shape table and rotation formula are reused from a well-known
 * public-domain-style reference implementation (see tetris.c).
 */
#ifndef TETRIS_H
#define TETRIS_H

#include <stdint.h>

void     tetris_init(void);
void     tetris_update(void);
void     tetris_draw(void);
uint32_t tetris_score(void);
int      tetris_finished(void);

/*
 * Test-only accessors/mutators for sw/test.
 * Board cells: 0 = empty, 1..7 = locked piece colour id (piece index + 1).
 * row in [0,20), col in [0,10).
 */
int     tetris_debug_piece(void);      /* current falling piece, 0..6 (I,O,S,Z,T,L,J) */
int     tetris_debug_rot(void);        /* current rotation, 0..3 */
int     tetris_debug_x(void);          /* current board-space offset (top-left of its 4x4 box) */
int     tetris_debug_y(void);
int     tetris_debug_next_piece(void); /* the piece shown in the NEXT preview / spawned next */
int     tetris_debug_tick_interval(void);

/* Forces the falling piece's piece/rotation/offset directly; caller must
 * pick a non-colliding state (test hook only). */
void    tetris_debug_set_piece(int piece, int rot, int x, int y);
void    tetris_debug_set_next_piece(int piece);

uint8_t tetris_debug_cell(int row, int col);
void    tetris_debug_set_cell(int row, int col, uint8_t color_id);

#endif
