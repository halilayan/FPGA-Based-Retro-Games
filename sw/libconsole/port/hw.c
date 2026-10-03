/*
 * port/hw.c -- kbd.h hardware port for Basys3.
 *
 * kbd_poll() merges two sources into the shared decoder (kbd.c):
 * kbd_axi_if.vhd (PS/2 via the board's USB HID host, through a dual
 * AXI GPIO) and the UART RX FIFO (a PC-side relay for keyboards the
 * USB HID host can't enumerate).
 *
 * Several base addresses below are placeholders pending confirmation
 * against the real Block Design's Address Editor.
 */
#include "kbd.h"
#include "gfx.h"
#include "sys.h"
#include "joystick.h"
#include "pal.h"
#include <stdint.h>

/* ---- Frame buffer ---- */
#define FB_BASE 0xC0000000u

void gfx_init(void)
{
    g_fb = (volatile uint8_t *)FB_BASE;
}

#define GPU_BASE   0xC4001000u
#define GPU_STATUS (*(volatile uint32_t *)(GPU_BASE + 0x00u)) /* bit0 = VBLANK pending, sticky, any write clears it */

void sys_wait_vblank(void)
{
    while ((GPU_STATUS & 0x1u) == 0u) {
    }
    GPU_STATUS = 0u;
}

/* console_gpu_axi.vhd's own base - GPU_BASE is that same peripheral's
 * "GPU regs" sub-region; the palette region sits at offset 0, one 32-bit
 * word per entry. */
#define PAL_BASE    (GPU_BASE - 0x1000u)
#define PAL_ENTRY(idx) (*(volatile uint32_t *)(PAL_BASE + (uint32_t)(idx) * 4u))

void pal_set_color(uint8_t idx, uint8_t r, uint8_t g, uint8_t b)
{
    PAL_ENTRY(idx) = ((uint32_t)(r & 0xFu) << 8) | ((uint32_t)(g & 0xFu) << 4) | (uint32_t)(b & 0xFu);
}

/* The palette region is write-only on real hardware (same limitation as
 * gfx_get_pixel()), always 0. */
void pal_get_color(uint8_t idx, uint8_t *r, uint8_t *g, uint8_t *b)
{
    (void)idx;
    *r = 0;
    *g = 0;
    *b = 0;
}

/* BLT_BASE/ASSET_BASE are placeholders - confirm against the Address
 * Editor once console_gpu_axi.vhd and asset_rom.vhd are wired in. */
#define BLT_BASE   0xC4002000u
#define BLT_CTRL   (*(volatile uint32_t *)(BLT_BASE + 0x00u))
#define BLT_DST    (*(volatile uint32_t *)(BLT_BASE + 0x04u))
#define BLT_SIZE   (*(volatile uint32_t *)(BLT_BASE + 0x08u))
#define BLT_COLOR  (*(volatile uint32_t *)(BLT_BASE + 0x10u))
#define BLT_STATUS (*(volatile uint32_t *)(BLT_BASE + 0x18u))

#define BLT_OP_FILL 0u

#define ASSET_BASE 0xC0020000u

/*
 * gfx_clear is the only hw.c drawing call that's blitter-accelerated:
 * it always covers the full screen, where the blitter's per-pixel win
 * is large. Still synchronous - waits for BLT_STATUS's busy bit before
 * returning, so callers see pixels in place either way.
 *
 * blt_fill does no negative-coordinate clipping; it's only ever called
 * with (0, 0, FB_W, FB_H).
 */
static void blt_wait_idle(void)
{
    while ((BLT_STATUS & 0x1u) != 0u) {
    }
}

static void blt_fill(int x, int y, int w, int h, uint8_t color)
{
    BLT_DST   = ((uint32_t)y << 10) | (uint32_t)x;
    BLT_SIZE  = ((uint32_t)h << 10) | (uint32_t)w;
    BLT_COLOR = color;
    BLT_CTRL  = (BLT_OP_FILL << 1) | 0x1u;
    blt_wait_idle();
}

void gfx_clear(uint8_t color)
{
    blt_fill(0, 0, FB_W, FB_H, color);
}

/*
 * gfx_fill_rect/gfx_sprite/gfx_sprite_key use a plain CPU loop, not the
 * blitter, same as host.c: per-call AXI4-Lite register-write overhead
 * dominates for the many small, frequent draws games make with these,
 * and caused real tearing/slowdown when blitter-accelerated.
 */
void gfx_fill_rect(int x, int y, int w, int h, uint8_t color)
{
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            gfx_pixel(x + i, y + j, color);
        }
    }
}

void gfx_sprite(int x, int y, const uint8_t *data, int w, int h)
{
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            gfx_pixel(x + i, y + j, data[(uint32_t)j * w + i]);
        }
    }
}

void gfx_sprite_key(int x, int y, const uint8_t *data, int w, int h, uint8_t key_color)
{
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            uint8_t c = data[(uint32_t)j * w + i];
            if (c != key_color) {
                gfx_pixel(x + i, y + j, c);
            }
        }
    }
}

const uint8_t *gfx_load_asset(int offset, const uint8_t *data, int size)
{
    volatile uint8_t *dst = (volatile uint8_t *)(ASSET_BASE + (uint32_t)offset);
    for (int i = 0; i < size; i++) {
        dst[i] = data[i];
    }
    return (const uint8_t *)dst;
}

/* ---- AXI GPIO for kbd_axi_if (placeholder address, see note above) ---- */
#define KBD_GPIO_BASE     0x40000000u
#define KBD_GPIO_DATA1    (*(volatile uint32_t *)(KBD_GPIO_BASE + 0x00u)) /* ch1: [7:0]=code [8]=empty */
#define KBD_GPIO_DATA2    (*(volatile uint32_t *)(KBD_GPIO_BASE + 0x08u)) /* ch2: [0]=read strobe */

/* ---- AXI UART Lite (PG142), same peripheral main.c's TX side uses ---- */
#define UART_BASE              0x40600000u
#define UART_RX_FIFO_REG       (*(volatile uint32_t *)(UART_BASE + 0x00u))
#define UART_TX_FIFO_REG       (*(volatile uint32_t *)(UART_BASE + 0x04u))
#define UART_STAT_REG          (*(volatile uint32_t *)(UART_BASE + 0x08u))
#define UART_STAT_RX_VALID     0x1u   /* STAT_REG bit0: RX FIFO has data */
#define UART_STAT_TX_FIFO_FULL 0x8u   /* STAT_REG bit3: TX FIFO full */

/* Polled UART TX; translates \n to \r\n. */
void sys_write_str(const char *s)
{
    while (*s != '\0') {
        if (*s == '\n') {
            while ((UART_STAT_REG & UART_STAT_TX_FIFO_FULL) != 0u) {
            }
            UART_TX_FIFO_REG = (uint32_t)(uint8_t)'\r';
        }
        while ((UART_STAT_REG & UART_STAT_TX_FIFO_FULL) != 0u) {
        }
        UART_TX_FIFO_REG = (uint32_t)(uint8_t)*s;
        s++;
    }
}

static void kbd_axi_if_poll(void)
{
    /* Drains up to scancode_fifo.vhd's DEPTH (16) bytes per call.
     * Draining only one byte/frame let a burst of extended-key bytes
     * overflow the FIFO and drop a break code, leaving a key stuck down.
     * Bounded at 16 rather than unconditional: KBD_GPIO_BASE is still a
     * placeholder that currently aliases a plain GPIO which never sets
     * the FIFO-empty bit, so an unbounded loop would hang waiting for a
     * flag that's never set. */
    for (int i = 0; i < 16; i++) {
        uint32_t ch1 = KBD_GPIO_DATA1;
        if ((ch1 & 0x100u) != 0u) {
            return;  /* FIFO empty */
        }
        kbd_feed_byte((uint8_t)(ch1 & 0xFFu));

        /* Pop handshake: rising edge on the strobe pops one entry (see
         * kbd_axi_if.vhd); always leave it low afterwards so the next
         * poll's rising edge is armed. */
        KBD_GPIO_DATA2 = 1u;
        KBD_GPIO_DATA2 = 0u;
    }
}

static void kbd_uart_relay_poll(void)
{
    /* Drain whatever tools/kbd_relay.py has queued since the last poll;
     * an unbounded loop is safe here because the relay only ever sends a
     * few bytes per physical key event. */
    while ((UART_STAT_REG & UART_STAT_RX_VALID) != 0u) {
        kbd_feed_byte((uint8_t)UART_RX_FIFO_REG);
    }
}

/*
 * JOY_BTN_GPIO_BASE: a 1-bit AXI GPIO fed by the joystick's button pin
 * through debounce.vhd. Confirmed via the Address Editor; note it
 * currently aliases the same address KBD_GPIO_BASE assumes above for
 * kbd_axi_if.vhd (not yet wired in) - give that a different address
 * once it is.
 *
 * XADC_BASE: the XADC Wizard IP's AXI4-Lite base address; offsets below
 * follow Xilinx PG019's DRP-mirror register map. See the wiring guide
 * for electrical safety notes before connecting anything to the XADC
 * pins.
 */
#define JOY_BTN_GPIO_BASE (*(volatile uint32_t *)0x40000000u)

#define XADC_BASE        0x44A00000u
/* Vaux4 (X) and Vaux15 (Y): channels 0-3 were unavailable in the XADC Wizard. */
#define VAUX_X_CHANNEL   0x14u
#define VAUX_Y_CHANNEL   0x1Fu
#define XADC_CHANNEL_REG(ch) (*(volatile uint32_t *)(XADC_BASE + 0x200u + 4u * (ch)))

/*
 * XADC results are left-justified in a 16-bit field - the true 12-bit
 * code is the top bits, hence >>4 before handing it to joystick_read().
 */
/*
 * Joystick hardware is wired into the Block Design but disabled by
 * default; flip to 1 once physical wiring is complete. Left at 0,
 * joystick_poll() is a no-op, so an unwired/floating XADC input can't
 * inject spurious directions into keyboard-only play.
 */
#define JOYSTICK_ENABLED 0

#if JOYSTICK_ENABLED
static int xadc_read_12bit(uint32_t channel)
{
    return (int)((XADC_CHANNEL_REG(channel) >> 4) & 0x0FFFu);
}
#endif

void joystick_init(void)
{
}

void joystick_poll(void)
{
#if JOYSTICK_ENABLED
    int x = xadc_read_12bit(VAUX_X_CHANNEL);
    int y = xadc_read_12bit(VAUX_Y_CHANNEL);
    int button_down = (int)(JOY_BTN_GPIO_BASE & 0x1u);

    kbd_merge_pad_bits(joystick_read(x, y, button_down));
#endif
}

void kbd_init(void)
{
    kbd_reset_state();
    KBD_GPIO_DATA2 = 0u;
}

void kbd_poll(void)
{
    kbd_axi_if_poll();
    kbd_uart_relay_poll();
    joystick_poll();
    kbd_commit_frame();
}
