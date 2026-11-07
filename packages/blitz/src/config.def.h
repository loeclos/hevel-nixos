#ifndef BLITZ_CONFIG_H
#define BLITZ_CONFIG_H

#include <stdint.h>

#include <swc.h>
#include <xkbcommon/xkbcommon-keysyms.h>

/* modifier mask used by every keybind below (MOD aliases it) */
static const uint32_t blitz_mod = SWC_MOD_LOGO;
#define MOD blitz_mod

/* spawned programs (NULL-terminated argv for execvp) */
static const char *const blitz_term[] = { "hst", NULL };
static const char *const blitz_menu[] = { "neumenu_run", NULL };

/* 1px borders, no rounding, no shadows. colors are 0xAARRGGBB */
static const uint32_t border_width = 1;
static const uint32_t border_color_active = 0xffff8c00;
static const uint32_t border_color_inactive = 0xff3a3a3a;

/* flat backdrop when no wallpaper is set */
static const uint32_t background_color = 0xff141414;

/* wallpaper image path; "" disables the image (flat background_color) */
static const char *const wallpaper = "";
/* 0 = fill (cover + center crop), 1 = fit (contain + letterbox), 2 = tile */
static const uint32_t wallpaper_mode = 0;

/* keyboard pan step in pixels per keypress (eased animation) */
static const int scroll_step = 64;
/* multiplicative zoom increment per keypress */
static const float zoom_step = 0.1f;

/*
 * dwl-style bind table over the action enum (see blitz.c).
 * fields: { modifiers, keysym, action, argv-or-NULL }.
 * MOD aliases blitz_mod so a Nix-generated config.h only rewrites this file.
 */
static const struct blitz_bind blitz_binds[] = {
	{ MOD, XKB_KEY_Return, SPAWN, blitz_term },
	{ MOD, XKB_KEY_r, SPAWN, blitz_menu },
	{ MOD, XKB_KEY_q, KILL, NULL },
	{ MOD, XKB_KEY_f, FULLSCREEN, NULL },
	{ MOD, XKB_KEY_Left, SCROLL_LEFT, NULL },
	{ MOD, XKB_KEY_Right, SCROLL_RIGHT, NULL },
	{ MOD, XKB_KEY_Up, SCROLL_UP, NULL },
	{ MOD, XKB_KEY_Down, SCROLL_DOWN, NULL },
	{ MOD, XKB_KEY_period, CENTER, NULL },
	{ MOD, XKB_KEY_Tab, NEXT_FOCUS, NULL },
	{ MOD, XKB_KEY_equal, ZOOM_IN, NULL },
	{ MOD, XKB_KEY_minus, ZOOM_OUT, NULL },
	{ MOD, XKB_KEY_0, ZOOM_RESET, NULL },
	{ MOD | SWC_MOD_SHIFT, XKB_KEY_q, QUIT, NULL },
};

#endif /* BLITZ_CONFIG_H */
