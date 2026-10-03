/*
 * gamelist.h -- game registration table.
 *
 * game_list[] is const; per-game mutable state lives in each game's own
 * .c file, accessed through the score/finished function pointers here.
 */
#ifndef GAMELIST_H
#define GAMELIST_H

#include <stdint.h>

typedef enum { GAME_C, GAME_RTL } game_kind_t;

typedef struct {
    const char  *name;
    const char  *controls;  /* one-line control summary, shown by pause.c's "Kontroller" screen */
    game_kind_t  kind;
    void       (*init)(void);
    void       (*update)(void);
    void       (*draw)(void);
    uint32_t   (*score)(void);
    int        (*finished)(void);
} game_t;

extern const game_t game_list[];
extern const int    game_count;

#endif
