/*
 * kbd.c -- transport-agnostic PS/2 Set 2 scan code decoder (see kbd.h).
 *
 * Change KEY_SCANCODE to remap physical keys. Extended keys (arrows etc.)
 * arrive as 0xE0 followed by the code.
 */
#include "kbd.h"

typedef struct {
    uint8_t extended;
    uint8_t code;
} scancode_t;

static const scancode_t KEY_SCANCODE[K_COUNT] = {
    /* K_UP     */ { 1, 0x75 }, /* Up arrow    */
    /* K_DOWN   */ { 1, 0x72 }, /* Down arrow  */
    /* K_LEFT   */ { 1, 0x6B }, /* Left arrow  */
    /* K_RIGHT  */ { 1, 0x74 }, /* Right arrow */
    /* K_A      */ { 0, 0x1A }, /* Z           */
    /* K_B      */ { 0, 0x22 }, /* X           */
    /* K_START  */ { 0, 0x5A }, /* Enter       */
    /* K_SELECT */ { 0, 0x59 }, /* Right Shift */
    /* K_ESC    */ { 0, 0x76 }, /* Esc         */
    /* K_PAUSE  */ { 0, 0x4D }, /* P           */
};

static uint8_t  saw_e0;
static uint8_t  saw_f0;
static uint16_t cur_down;   /* live decoder state, updated per byte     */
static uint16_t joy_down;   /* current joystick bits, see kbd_merge_pad_bits */
static uint16_t poll_down;  /* snapshot as of the last kbd_commit_frame */
static uint16_t poll_prev;  /* snapshot before that, for hit()/up()     */

static int find_key(uint8_t extended, uint8_t code)
{
    for (int k = 0; k < K_COUNT; k++) {
        if (KEY_SCANCODE[k].extended == extended && KEY_SCANCODE[k].code == code) {
            return k;
        }
    }
    return -1;
}

void kbd_reset_state(void)
{
    saw_e0 = 0;
    saw_f0 = 0;
    cur_down = 0;
    joy_down = 0;
    poll_down = 0;
    poll_prev = 0;
}

void kbd_feed_byte(uint8_t b)
{
    if (b == 0xE0) {
        saw_e0 = 1;
        return;
    }
    if (b == 0xF0) {
        saw_f0 = 1;
        return;
    }

    int k = find_key(saw_e0, b);
    if (k >= 0) {
        if (saw_f0) {
            cur_down = (uint16_t)(cur_down & ~(1u << k));
        } else {
            cur_down = (uint16_t)(cur_down | (1u << k));
        }
    }
    /* Untracked key: byte consumed, no state change. */
    saw_e0 = 0;
    saw_f0 = 0;
}

void kbd_merge_pad_bits(uint16_t bits)
{
    joy_down = bits;
}

void kbd_commit_frame(void)
{
    poll_prev = poll_down;
    poll_down = (uint16_t)(cur_down | joy_down);
}

int kbd_down(int key)
{
    return (poll_down >> key) & 1u;
}

int kbd_hit(int key)
{
    return ((poll_down >> key) & 1u) && !((poll_prev >> key) & 1u);
}

int kbd_up(int key)
{
    return !((poll_down >> key) & 1u) && ((poll_prev >> key) & 1u);
}

uint16_t kbd_pad_state(void)
{
    return poll_down;
}
