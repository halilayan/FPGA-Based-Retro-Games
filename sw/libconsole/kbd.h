/*
 * kbd.h -- libconsole keyboard abstraction.
 *
 * Two sources feed key events into this module: kbd_axi_if.vhd (PS/2 via
 * the board's USB HID host) and a PC-side UART relay. Both carry raw
 * PS/2 Set 2 scan code bytes, decoded identically by kbd_feed_byte().
 */
#ifndef KBD_H
#define KBD_H

#include <stdint.h>

enum { K_UP, K_DOWN, K_LEFT, K_RIGHT,
       K_A, K_B, K_START, K_SELECT, K_ESC, K_PAUSE, K_COUNT };

/* Port-specific (implemented once in port/hw.c, once in port/host.c). */
void kbd_init(void);
void kbd_poll(void);          /* once per frame */

/* Shared (kbd.c), queries the state kbd_poll() last committed. */
int      kbd_down(int key);   /* held right now */
int      kbd_hit(int key);    /* pressed this frame */
int      kbd_up(int key);     /* released this frame */
uint16_t kbd_pad_state(void); /* bit N = K_* value N; bits 10-15 reserved */

/*
 * Shared decoder primitives (kbd.c), used by both ports' kbd_poll() and
 * by sw/test to inject synthetic scan code streams.
 */
void kbd_reset_state(void);   /* clears decoder + press state */
void kbd_feed_byte(uint8_t b);
void kbd_commit_frame(void);  /* snapshots state for kbd_hit()/kbd_up() */

/*
 * joystick.h ORs its own bits in here each frame, alongside the PS/2
 * decoder's state. Call before kbd_commit_frame(). This is a level, not
 * an edge: pass 0 when not pressed, and resend the current state every
 * frame - there is no separate "release" event to clear a bit.
 */
void kbd_merge_pad_bits(uint16_t bits);

#endif
