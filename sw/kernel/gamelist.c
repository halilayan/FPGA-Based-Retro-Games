/*
 * gamelist.c -- see gamelist.h. Add new games here as they're written.
 *
 * v1: only the games that fit in the current 64 KiB LMB budget are
 * registered here (Pong 2P dropped to make room for real palette colours -
 * near-identical to Pong anyway). invaders/minesweeper/asteroids/pacman
 * are written, tested, and coloured, but don't fit yet.
 */
#include "gamelist.h"
#include "pong.h"
#include "snake.h"
#include "breakout.h"
#include "tetris.h"
#include "frogger.h"
#include "flappy.h"

const game_t game_list[] = {
    { "PONG", "YON: YUKARI/ASAGI", GAME_C, pong_init, pong_update, pong_draw, pong_score, pong_finished },
    { "SNAKE", "YON: OK TUSLARI", GAME_C, snake_init, snake_update, snake_draw, snake_score, snake_finished },
    { "BREAKOUT", "YON: SOL/SAG", GAME_C, breakout_init, breakout_update, breakout_draw, breakout_score, breakout_finished },
    { "TETRIS", "SOL/SAG:KAYDIR YUKARI:DONDUR ASAGI:HIZLI", GAME_C, tetris_init, tetris_update, tetris_draw, tetris_score, tetris_finished },
    { "FROGGER", "YON: OK TUSLARI", GAME_C, frogger_init, frogger_update, frogger_draw, frogger_score, frogger_finished },
    { "FLAPPY BIRD", "ZIPLA: Z", GAME_C, flappy_init, flappy_update, flappy_draw, flappy_score, flappy_finished },
};

const int game_count = (int)(sizeof(game_list) / sizeof(game_list[0]));
