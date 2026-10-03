/*
 * pause.h -- pause menu: resume, restart, view controls, or quit.
 */
#ifndef PAUSE_H
#define PAUSE_H

#include "gamelist.h"

typedef enum {
    PAUSE_NONE = 0,   /* stay in the pause menu */
    PAUSE_RESUME,     /* return to the game */
    PAUSE_RESTART,    /* reset the game */
    PAUSE_QUIT        /* return to the main menu */
} pause_result_t;

void           pause_open(const game_t *g);
pause_result_t pause_update(const game_t *g);
void           pause_close(void);

#endif
