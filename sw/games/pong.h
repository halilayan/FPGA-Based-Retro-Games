/*
 * pong.h -- Single-player Pong against a simple AI paddle.
 */
#ifndef PONG_H
#define PONG_H

#include <stdint.h>

void     pong_init(void);
void     pong_update(void);
void     pong_draw(void);
uint32_t pong_score(void);
int      pong_finished(void);

/* Test-only accessors/mutator for sw/test. */
int  pong_debug_player_y(void);
int  pong_debug_ai_y(void);
int  pong_debug_ball_x(void);
int  pong_debug_ball_y(void);
int  pong_debug_ball_vx(void);
int  pong_debug_ball_vy(void);
void pong_debug_set_ball(int x, int y, int vx, int vy);

#endif
