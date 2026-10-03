/*
 * frogger.h -- Classic lane-crossing Frogger.
 * Controls: discrete one-cell hops via kbd_hit(), not continuous kbd_down().
 */
#ifndef FROGGER_H
#define FROGGER_H

#include <stdint.h>

void     frogger_init(void);
void     frogger_update(void);
void     frogger_draw(void);
uint32_t frogger_score(void);
int      frogger_finished(void);

/* Test-only accessors/mutators for sw/test. */
int  frogger_debug_frog_x(void);
int  frogger_debug_frog_y(void);
/* Forces the frog's grid cell directly; also clears any pending dirty-move
 * state. */
void frogger_debug_set_frog(int x, int y);

int  frogger_debug_lives(void);

/* lane: 0..3, obj: 0 or 1. x is the object's lane-local pixel x (0 = grid's
 * left edge, wraps at GRID_W*CELL). */
void frogger_debug_set_car(int lane, int obj, int x);
void frogger_debug_set_log(int lane, int obj, int x);
int  frogger_debug_car_x(int lane, int obj);
int  frogger_debug_log_x(int lane, int obj);

/* slot in [0, HOME_SLOTS). */
int  frogger_debug_home_filled(int slot);
int  frogger_debug_homes_filled(void);  /* count of slots filled so far */

#endif
