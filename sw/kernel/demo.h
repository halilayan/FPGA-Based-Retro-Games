/*
 * demo.h -- sanity demo exercising gfx.c + kbd.c + sys.c together,
 * portable between the board (hw.c) and PC (host.c) backends.
 */
#ifndef DEMO_H
#define DEMO_H

void demo_init(void);
void demo_step(void);  /* one iteration: poll input, update, draw */

#endif
