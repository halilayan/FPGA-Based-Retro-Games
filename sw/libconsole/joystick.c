/*
 * joystick.c -- see joystick.h. Deadzone/threshold conversion only - the
 * port-specific hardware access (joystick_init/joystick_poll) lives in
 * port/hw.c and port/host.c.
 */
#include "joystick.h"
#include "kbd.h"

#define CENTER   (JOYSTICK_ADC_MAX / 2)
#define DEADZONE 600 /* +/- around CENTER treated as "centred", no direction */

uint16_t joystick_read(int x_raw, int y_raw, int button_down)
{
    uint16_t bits = 0;
    int x_off = x_raw - CENTER;
    int y_off = y_raw - CENTER;

    /* Axis direction depends on how the module is wired (X/Y swap, axis
     * reversal) and can't be known without real hardware. If a direction
     * comes out reversed, swap the two comparisons for that axis here. */
    if (x_off < -DEADZONE) { bits |= (uint16_t)(1u << K_LEFT); }
    if (x_off > DEADZONE)  { bits |= (uint16_t)(1u << K_RIGHT); }
    if (y_off < -DEADZONE) { bits |= (uint16_t)(1u << K_UP); }
    if (y_off > DEADZONE)  { bits |= (uint16_t)(1u << K_DOWN); }
    if (button_down) { bits |= (uint16_t)(1u << K_START); }

    return bits;
}
