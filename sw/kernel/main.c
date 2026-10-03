/*
 * main.c -- KonsolOS entry point.
 *
 * Runs kernel_init() once, then drives kernel_step() in a loop synced to
 * VBLANK so drawing always starts at the beginning of a fresh frame.
 */
#include "kernel.h"
#include "sys.h"

int main(void)
{
    kernel_init();

    for (;;) {
        sys_wait_vblank();
        kernel_step();
    }
}
