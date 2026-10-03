/*
 * breakout.h -- classic brick-breaker (grid of bricks, paddle, bouncing ball).
 *
 * Same game_t contract shape as pong.h/snake.h - see sw/kernel/gamelist.h.
 */
#ifndef BREAKOUT_H
#define BREAKOUT_H

#include <stdint.h>

void     breakout_init(void);
void     breakout_update(void);
void     breakout_draw(void);
uint32_t breakout_score(void);
int      breakout_finished(void);

/* Test-only accessors/mutators for sw/test. */
int  breakout_debug_paddle_x(void);
void breakout_debug_set_paddle_x(int x);

int  breakout_debug_ball_x(void);
int  breakout_debug_ball_y(void);
int  breakout_debug_ball_vx(void);
int  breakout_debug_ball_vy(void);
void breakout_debug_set_ball(int x, int y, int vx, int vy);

int  breakout_debug_lives(void);
int  breakout_debug_bricks_left(void);

/* row in [0,BREAKOUT_ROWS), col in [0,BREAKOUT_COLS) - see breakout.c. */
int  breakout_debug_brick_alive(int row, int col);
void breakout_debug_kill_brick(int row, int col);

#endif
