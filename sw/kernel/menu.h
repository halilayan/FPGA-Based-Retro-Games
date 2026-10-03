/*
 * menu.h -- main game-selection menu: a name list with a cursor,
 * driven by game_list[]/game_count.
 */
#ifndef MENU_H
#define MENU_H

int  menu_update(int sel);  /* returns the (possibly unchanged) selection */
void menu_draw(int sel);

#endif
