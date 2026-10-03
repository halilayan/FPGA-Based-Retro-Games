/*
 * kernel.h -- KonsolOS state machine: BOOT -> MENU -> RUN -> PAUSE -> SCORE.
 *
 * kernel_step() runs one loop iteration; callable from main() or from
 * test code driving the state machine with synthetic key presses.
 */
#ifndef KERNEL_H
#define KERNEL_H

void kernel_init(void);
void kernel_step(void);

/* Test-only accessor. */
int kernel_state(void);

#endif
