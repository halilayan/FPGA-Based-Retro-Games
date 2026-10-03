/*
 * joystick.h -- KY-023 analog joystick support: a second input source
 * merged into kbd.h's pad state, not a separate gamepad.
 *
 * Two analog axes via the FPGA's XADC and one digital button; the
 * deadzone/direction conversion is done here in C for host testability.
 */
#ifndef JOYSTICK_H
#define JOYSTICK_H

#include <stdint.h>

/*
 * 12-bit unipolar XADC code (0..4095). The raw XADC register is
 * left-justified in a 16-bit word - shift down to this scale before
 * calling joystick_read (see hw.c).
 */
#define JOYSTICK_ADC_MAX 4095

/* Port-specific: hw.c reads the real XADC/GPIO registers, host.c is a
 * no-op (sw/test injects synthetic readings directly via joystick_read). */
void joystick_init(void);
void joystick_poll(void); /* once per frame - reads hardware, merges into kbd.h's pad state */

/*
 * Pure conversion: raw ADC codes for X/Y (centred at ADC_MAX/2) plus a
 * debounced button level, in; kbd.h's pad bitmask, out. No hardware
 * access or state, so sw/test can call it directly.
 */
uint16_t joystick_read(int x_raw, int y_raw, int button_down);

#endif
