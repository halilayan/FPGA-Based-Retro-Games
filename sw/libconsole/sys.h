/*
 * sys.h -- libconsole system services: tick counter, RNG, formatted
 * logging, and VBLANK sync.
 */
#ifndef SYS_H
#define SYS_H

#include <stdint.h>

void sys_init(void);
void sys_poll(void);       /* once per frame - advances sys_ticks() */
uint32_t sys_ticks(void);  /* frames elapsed since sys_init() */

/*
 * Blocks until the next VBLANK (GPU_STATUS sticky bit, cleared on read).
 * Call once per frame, before drawing, so the CPU never redraws mid-scan.
 * No-op on host builds.
 */
void sys_wait_vblank(void);

/*
 * 32-bit maximal-length Fibonacci LFSR (taps 32,22,2,1). This is the
 * software reference an eventual RTL version must match bit-for-bit for
 * the same seed.
 */
uint32_t sys_rng(void);
void     sys_srand(uint32_t seed);

void sys_log(const char *fmt, ...);  /* UART on hw, stdout on host */

/*
 * sys_log's formatter, exposed for sw/test to check its output precisely.
 * Not vsnprintf: on MicroBlaze bare-metal, newlib's printf family
 * overflows the 64 KiB LMB local memory. Supports %d %u %ld %lu %x %X
 * %s %%, plus zero-padded width on %x/%X; truncates safely if it would
 * overflow buf.
 */
void sys_format(char *buf, int buf_size, const char *fmt, ...);

/*
 * Port hook (not game-facing API): hands sys_log's formatted string to
 * whichever port is linked in - hw.c writes it to the UART, host.c to
 * stdout.
 */
void sys_write_str(const char *s);

#endif
