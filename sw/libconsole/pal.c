/*
 * pal.c -- see pal.h. Stub until real palette hardware exists.
 */
#include "pal.h"

static int depth;

void pal_push_dimmed(int percent)
{
    (void)percent;
    depth++;
}

void pal_pop(void)
{
    if (depth > 0) {
        depth--;
    }
}

int pal_debug_depth(void)
{
    return depth;
}
