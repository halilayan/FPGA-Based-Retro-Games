/*
 * pal.h -- palette control. console_gpu_axi.vhd's 256-entry CPU-writable
 * RGB444 table is real and AXI-mapped (see hw.c).
 *
 * pal_push_dimmed()/pal_pop() (pause-menu dimming) remain a no-op stub -
 * unrelated to real colour setting below.
 */
#ifndef PAL_H
#define PAL_H

#include <stdint.h>

void pal_push_dimmed(int percent);  /* push the current palette, load a dimmed variant */
void pal_pop(void);                 /* restore the previously pushed palette */

/* Test-only accessor: push/pop call count, to check the stack never
 * leaks across repeated pause/resume/quit cycles. */
int pal_debug_depth(void);

/*
 * pal_set_color(idx, r, g, b) -- writes palette entry idx (0-255) with a
 * real RGB444 colour. r/g/b are each a 4-bit nibble (0-15), the
 * hardware's own native precision. Entry 0 is the blitter's fixed
 * transparency key - leave it unused as a real colour.
 *
 * pal_get_color() -- test-only readback (real hardware's palette is
 * write-only, so hw.c's version always reports 0,0,0).
 */
void pal_set_color(uint8_t idx, uint8_t r, uint8_t g, uint8_t b);
void pal_get_color(uint8_t idx, uint8_t *r, uint8_t *g, uint8_t *b);

#endif
