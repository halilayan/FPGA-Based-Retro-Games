/*
 * flappy.h -- Flappy Bird clone: integer-physics bird, scrolling
 * pipe-pairs, single life, score = pipes passed.
 * Controls: K_A to flap, pressed-edge only.
 */
#ifndef FLAPPY_H
#define FLAPPY_H

#include <stdint.h>

void     flappy_init(void);
void     flappy_update(void);
void     flappy_draw(void);
uint32_t flappy_score(void);
int      flappy_finished(void);

/* Test-only accessors/mutators for sw/test.
 * Pipe index is in [0,1] (PIPE_COUNT); no bounds checking (test hook only). */
int  flappy_debug_bird_y(void);
int  flappy_debug_bird_vy(void);
void flappy_debug_set_bird(int y, int vy);

int  flappy_debug_pipe_x(int idx);
int  flappy_debug_pipe_gap_y0(int idx);     /* top of the gap (first open row) */
int  flappy_debug_pipe_scored(int idx);
void flappy_debug_set_pipe(int idx, int x, int gap_y0);

/* Counts full-column vs per-slice pipe redraws (reset by flappy_init()).
 * A pixel-content check alone can't tell the two paths apart, since both
 * produce identical output. */
uint32_t flappy_debug_full_redraw_count(void);
uint32_t flappy_debug_slice_redraw_count(void);

#endif
