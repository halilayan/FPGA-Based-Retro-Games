/*
 * snake.h -- Classic grid Snake.
 * Uses a fixed-size body array rather than a heap-allocated list, since
 * this project's bare-metal image has no heap.
 */
#ifndef SNAKE_H
#define SNAKE_H

#include <stdint.h>

void     snake_init(void);
void     snake_update(void);
void     snake_draw(void);
uint32_t snake_score(void);
int      snake_finished(void);

/* Test-only accessors/mutators for sw/test. */
int  snake_debug_head_x(void);
int  snake_debug_head_y(void);
int  snake_debug_length(void);
int  snake_debug_dir(void);          /* 0=up 1=down 2=left 3=right */
int  snake_debug_food_x(void);
int  snake_debug_food_y(void);
int  snake_debug_tick_interval(void);

/* Overwrites the whole body (xs[0]/ys[0] = head) and heading. len must be
 * <= MAX_LEN; no bounds checking (test hook only). */
void snake_debug_force_body(const int *xs, const int *ys, int len, int dir);
void snake_debug_force_food(int x, int y);

#endif
