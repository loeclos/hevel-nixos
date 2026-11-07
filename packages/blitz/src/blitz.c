/* blitz: keyboard-driven infinite-canvas Wayland desktop.
 *
 * A single-file compositor on neuswc: hevel's invisible infinite plane fused
 * with Hyprland-grade keybind configurability (via config.h, no rebuild pain
 * beyond `make`). Software-rendered, dependency-light: no GPU stack, no
 * portals, no animation theater.
 *
 * Everything is mouseless except mod+left-drag move and mod+right-drag
 * resize. Plain clicks always reach clients.
 *
 * Build: cc $(pkg-config --cflags swc wayland-client) blitz.c \
 *            $(pkg-config --libs swc wayland-client)
 * Run:   swc-launch ./blitz
 *
 * neuswc API surface used (see <swc.h>):
 *   windows:   swc_window_set_handler/show/hide/focus/close,
 *              swc_window_set_stacked/fullscreen,
 *              swc_window_set_position/geometry/get_geometry,
 *              swc_window_set_border, swc_window_begin/end_move,
 *              swc_window_begin/end_resize, swc_window_at
 *   bindings:  swc_add_binding (KEY + BUTTON)
 *   view:      swc_set_zoom/swc_get_zoom,
 *              swc_cursor_position
 *   screens:   swc_screen_set_handler
 *   core:      swc_initialize/swc_finalize, wl_display_add_socket_auto
 *   wallpaper: in-process layer-shell client against neuswc's
 *              zwlr_layer_shell_v1 (v5) server: one background-layer surface,
 *              exclusive-zone -1, full-output anchor, shm buffers fed by
 *              stb_image-decoded pixels.
 */

#define _POSIX_C_SOURCE 200809L

#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <swc.h>
#include <wayland-client.h>
#include <wayland-client-protocol.h>
#include <wayland-server.h>
#include <wayland-util.h>
#include <xkbcommon/xkbcommon-keysyms.h>

#ifdef __linux__
#include <linux/input-event-codes.h>
#else
#define BTN_LEFT 0x110
#define BTN_RIGHT 0x111
#endif

/* stb_image.h is provided next to the sources at build time, not vendored. */
#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_SIMD
#if defined(__GNUC__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#pragma GCC diagnostic ignored "-Wsign-compare"
#pragma GCC diagnostic ignored "-Wtype-limits"
#endif
#include "stb_image.h"
#if defined(__GNUC__)
#pragma GCC diagnostic pop
#endif

/* Action enum: the config.h bind table dispatches over this. */
enum blitz_action {
	SPAWN = 0,
	KILL,
	FULLSCREEN,
	ZOOM_IN,
	ZOOM_OUT,
	ZOOM_RESET,
	SCROLL_UP,
	SCROLL_DOWN,
	SCROLL_LEFT,
	SCROLL_RIGHT,
	CENTER,
	NEXT_FOCUS,
	QUIT
};

/* dwl-style bind row: { modifiers, keysym, action, argv-or-NULL }. */
struct blitz_bind {
	uint32_t mods;
	uint32_t keysym;
	enum blitz_action action;
	const char *const *cmd;
};

/* Owner-editable config (config.h is a copy of config.def.h). */
#include "config.h"

#define LENGTH(a) (sizeof(a) / sizeof((a)[0]))
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))

/* ------------------------------------------------------------------ */
/* compositor state                                                    */
/* ------------------------------------------------------------------ */

struct blitz_win {
	struct wl_list link;
	struct swc_window *w;
	bool fullscreen;
	struct swc_rectangle saved;
};

struct blitz_screen {
	struct wl_list link;
	struct swc_screen *s;
};

static struct wl_display *g_dpy;
static struct wl_event_loop *g_loop;
static struct wl_list g_wins;
static struct wl_list g_screens;
static struct blitz_screen *g_active;
static struct swc_window *g_focused;

/* smooth infinite-plane animation: pending pan (px) + zoom target */
static int32_t g_pan_x;
static int32_t g_pan_y;
static float g_zoom_target = 1.0f;
static struct wl_event_source *g_anim;

/* mouse drag state (mod+left move / mod+right resize only) */
static struct swc_window *g_grab;
static bool g_grab_move;

static void
die(const char *msg)
{
	fprintf(stderr, "blitz: %s\n", msg);
	exit(EXIT_FAILURE);
}

/* ------------------------------------------------------------------ */
/* small helpers                                                       */
/* ------------------------------------------------------------------ */

static struct blitz_screen *
first_screen(void)
{
	if (wl_list_empty(&g_screens))
		return NULL;
	return wl_container_of(g_screens.next, (struct blitz_screen *)NULL,
	    link);
}

static bool
cursor_global(int32_t *x, int32_t *y)
{
	int32_t fx = 0, fy = 0;

	/* swc reports wl_fixed 24.8 units; convert to logical pixels */
	if (!swc_cursor_position(&fx, &fy))
		return false;
	*x = fx / 256;
	*y = fy / 256;
	return true;
}

static struct blitz_win *
find_win(struct swc_window *w)
{
	struct blitz_win *bw;

	wl_list_for_each(bw, &g_wins, link) {
		if (bw->w == w)
			return bw;
	}
	return NULL;
}

static struct swc_window *
window_at_cursor(void)
{
	int32_t x, y;

	if (!cursor_global(&x, &y))
		return NULL;
	return swc_window_at(x, y);
}

static void
move_all(int32_t dx, int32_t dy)
{
	struct blitz_win *bw;
	struct swc_rectangle g;

	if (dx == 0 && dy == 0)
		return;
	wl_list_for_each(bw, &g_wins, link) {
		if (bw->fullscreen)
			continue;
		if (!swc_window_get_geometry(bw->w, &g))
			continue;
		swc_window_set_position(bw->w, g.x + dx, g.y + dy);
	}
}

/* ------------------------------------------------------------------ */
/* focus + borders (1px, active/inactive, no rounding)                 */
/* ------------------------------------------------------------------ */

static bool
win_visible_on(struct blitz_win *bw, struct blitz_screen *s)
{
	struct swc_rectangle wg;
	int32_t sx, sy;
	uint32_t sw, sh;

	if (!bw || !s)
		return false;
	if (!swc_window_get_geometry(bw->w, &wg))
		return false;
	sx = s->s->geometry.x;
	sy = s->s->geometry.y;
	sw = s->s->geometry.width;
	sh = s->s->geometry.height;
	return wg.x + (int32_t)wg.width > sx && wg.x < sx + (int32_t)sw &&
	    wg.y + (int32_t)wg.height > sy && wg.y < sy + (int32_t)sh;
}

/* pan (animated) so the focused window ends up centered on screen */
static void
center_focused(void);

static void
focus_window(struct swc_window *w, bool center)
{
	struct blitz_win *bw = w ? find_win(w) : NULL;

	if (g_focused != NULL)
		swc_window_set_border(g_focused, border_color_inactive,
		    border_width, 0, 0);
	if (w != NULL && bw != NULL) {
		swc_window_set_border(w, border_color_active, border_width, 0,
		    0);
		swc_window_focus(w);
	} else {
		w = NULL;
		swc_window_focus(NULL);
	}
	g_focused = w;
	if (w != NULL && center)
		center_focused();
}

/* ------------------------------------------------------------------ */
/* smooth animation: eased pan + eased zoom-to-cursor                  */
/* ------------------------------------------------------------------ */

static int
anim_tick(void *data)
{
	bool more = false;
	float z = swc_get_zoom();

	(void)data;
	if (z != g_zoom_target) {
		float nz = z + (g_zoom_target - z) * 0.25f;

		if (nz > g_zoom_target - 0.005f && nz < g_zoom_target + 0.005f)
			nz = g_zoom_target;

		/* zoom-to-cursor: shift the plane so the point under the
		 * cursor stays under the cursor. neuswc zooms about the
		 * screen center c: rendered(p) = c + (world - c) * z, so a
		 * zoom z0 -> z1 must shift windows by
		 * s = (p - c) * (1/z1 - 1/z0). */
		if (nz != z) {
			int32_t px = 0, py = 0;
			struct blitz_screen *s = g_active ?
			    g_active :
			    first_screen();

			if (s != NULL && cursor_global(&px, &py)) {
				int32_t cx = s->s->geometry.x +
				    (int32_t)s->s->geometry.width / 2;
				int32_t cy = s->s->geometry.y +
				    (int32_t)s->s->geometry.height / 2;
				float k = 1.0f / nz - 1.0f / z;

				move_all((int32_t)((float)(px - cx) * k),
				    (int32_t)((float)(py - cy) * k));
			}
		}
		swc_set_zoom(nz);
		if (nz != g_zoom_target)
			more = true;
	}
	if (g_pan_x != 0 || g_pan_y != 0) {
		int32_t sx = g_pan_x / 4;
		int32_t sy = g_pan_y / 4;

		if (sx == 0 && g_pan_x != 0)
			sx = g_pan_x > 0 ? 1 : -1;
		if (sy == 0 && g_pan_y != 0)
			sy = g_pan_y > 0 ? 1 : -1;
		move_all(sx, sy);
		g_pan_x -= sx;
		g_pan_y -= sy;
		more = true;
	}
	if (more && g_anim != NULL)
		wl_event_source_timer_update(g_anim, 16);
	return 0;
}

static void
anim_kick(void)
{
	if (g_anim == NULL)
		g_anim = wl_event_loop_add_timer(g_loop, anim_tick, NULL);
	if (g_anim != NULL)
		wl_event_source_timer_update(g_anim, 16);
}

static void
pan_by(int32_t dx, int32_t dy)
{
	g_pan_x += dx;
	g_pan_y += dy;
	anim_kick();
}

static void
center_focused(void)
{
	struct blitz_win *bw = g_focused ? find_win(g_focused) : NULL;
	struct blitz_screen *s = g_active ? g_active : first_screen();
	struct swc_rectangle wg;

	if (bw == NULL || s == NULL)
		return;
	if (!swc_window_get_geometry(bw->w, &wg))
		return;
	if (wg.width == 0 || wg.height == 0)
		return;
	pan_by(s->s->geometry.x + (int32_t)s->s->geometry.width / 2 -
	    (wg.x + (int32_t)wg.width / 2),
	    s->s->geometry.y + (int32_t)s->s->geometry.height / 2 -
	    (wg.y + (int32_t)wg.height / 2));
}

static void
zoom_by(float factor)
{
	g_zoom_target *= factor;
	g_zoom_target = MIN(4.0f, MAX(0.25f, g_zoom_target));
	anim_kick();
}

/* ------------------------------------------------------------------ */
/* actions                                                             */
/* ------------------------------------------------------------------ */

static void
do_spawn(const char *const *cmd)
{
	pid_t pid;

	if (cmd == NULL || cmd[0] == NULL)
		return;
	pid = fork();
	if (pid < 0)
		return;
	if (pid == 0) {
		char *const *argv = (char *const *)cmd;

		if (setsid() < 0)
			_exit(127);
		execvp(argv[0], argv);
		_exit(127);
	}
}

static void
do_next_focus(void)
{
	struct blitz_win *bw, *next = NULL;
	bool after = (g_focused == NULL);

	if (wl_list_empty(&g_wins))
		return;
	wl_list_for_each(bw, &g_wins, link) {
		if (after) {
			next = bw;
			break;
		}
		if (bw->w == g_focused)
			after = true;
	}
	if (next == NULL)
		next = wl_container_of(g_wins.next, (struct blitz_win *)NULL,
		    link);
	focus_window(next->w, true);
}

static void
do_fullscreen(void)
{
	struct blitz_win *bw = g_focused ? find_win(g_focused) : NULL;
	struct blitz_screen *s = g_active ? g_active : first_screen();

	if (bw == NULL || s == NULL)
		return;
	if (!bw->fullscreen) {
		if (!swc_window_get_geometry(bw->w, &bw->saved))
			return;
		bw->fullscreen = true;
		swc_window_set_border(bw->w, border_color_active, 0, 0, 0);
		swc_window_set_fullscreen(bw->w, s->s);
	} else {
		bw->fullscreen = false;
		swc_window_set_stacked(bw->w);
		swc_window_set_border(bw->w, border_color_active, border_width,
		    0, 0);
		if (bw->saved.width > 0 && bw->saved.height > 0)
			swc_window_set_geometry(bw->w, &bw->saved);
	}
}

static void
action_handler(void *data, uint32_t time, uint32_t value, uint32_t state)
{
	const struct blitz_bind *b = data;

	(void)time;
	(void)value;
	if (b == NULL || state != WL_KEYBOARD_KEY_STATE_PRESSED)
		return;
	switch (b->action) {
	case SPAWN:
		do_spawn(b->cmd);
		break;
	case KILL:
		if (g_focused != NULL)
			swc_window_close(g_focused);
		break;
	case FULLSCREEN:
		do_fullscreen();
		break;
	case ZOOM_IN:
		zoom_by(1.0f + zoom_step);
		break;
	case ZOOM_OUT:
		zoom_by(1.0f / (1.0f + zoom_step));
		break;
	case ZOOM_RESET:
		g_zoom_target = 1.0f;
		anim_kick();
		break;
	case SCROLL_UP:
		pan_by(0, scroll_step);
		break;
	case SCROLL_DOWN:
		pan_by(0, -scroll_step);
		break;
	case SCROLL_LEFT:
		pan_by(scroll_step, 0);
		break;
	case SCROLL_RIGHT:
		pan_by(-scroll_step, 0);
		break;
	case CENTER:
		center_focused();
		break;
	case NEXT_FOCUS:
		do_next_focus();
		break;
	case QUIT:
		wl_display_terminate(g_dpy);
		break;
	}
}

/* mod+left-drag move / mod+right-drag resize; plain clicks hit clients. */
static void
button_move(void *data, uint32_t time, uint32_t value, uint32_t state)
{
	(void)data;
	(void)time;
	(void)value;
	if (state == WL_POINTER_BUTTON_STATE_PRESSED) {
		struct swc_window *w = window_at_cursor();

		if (w == NULL)
			w = g_focused;
		if (w == NULL)
			return;
		focus_window(w, false);
		g_grab = w;
		g_grab_move = true;
		swc_window_begin_move(w);
	} else if (g_grab != NULL && g_grab_move) {
		swc_window_end_move(g_grab);
		g_grab = NULL;
	}
}

static void
button_resize(void *data, uint32_t time, uint32_t value, uint32_t state)
{
	(void)data;
	(void)time;
	(void)value;
	if (state == WL_POINTER_BUTTON_STATE_PRESSED) {
		struct swc_window *w = window_at_cursor();

		if (w == NULL)
			w = g_focused;
		if (w == NULL)
			return;
		focus_window(w, false);
		g_grab = w;
		g_grab_move = false;
		swc_window_begin_resize(w,
		    SWC_WINDOW_EDGE_RIGHT | SWC_WINDOW_EDGE_BOTTOM);
	} else if (g_grab != NULL && !g_grab_move) {
		swc_window_end_resize(g_grab);
		g_grab = NULL;
	}
}

static void
setup_binds(void)
{
	size_t i;

	for (i = 0; i < LENGTH(blitz_binds); i++) {
		const struct blitz_bind *b = &blitz_binds[i];

		swc_add_binding(SWC_BINDING_KEY, b->mods, b->keysym,
		    action_handler, (void *)b);
	}
	/* mouse binds are hardcoded, never remapped through the table */
	swc_add_binding(SWC_BINDING_BUTTON, blitz_mod, BTN_LEFT, button_move,
	    NULL);
	swc_add_binding(SWC_BINDING_BUTTON, blitz_mod, BTN_RIGHT, button_resize,
	    NULL);
}

/* ------------------------------------------------------------------ */
/* swc manager callbacks                                               */
/* ------------------------------------------------------------------ */

static void
on_win_destroy(void *data)
{
	struct blitz_win *bw = data;
	struct blitz_win *next = NULL;

	if (bw == NULL)
		return;
	if (g_grab == bw->w)
		g_grab = NULL;
	wl_list_remove(&bw->link);
	if (g_focused == bw->w) {
		if (!wl_list_empty(&g_wins))
			next = wl_container_of(g_wins.next,
			    (struct blitz_win *)NULL, link);
		focus_window(next ? next->w : NULL, false);
	}
	free(bw);
}

static void
on_win_entered(void *data)
{
	struct blitz_win *bw = data;
	struct blitz_screen *s;

	if (bw == NULL || bw->w == g_focused)
		return;
	/* pointer-following focus; only recenter if it is off-screen so the
	 * mouse never yanks the plane out from under the user. */
	s = g_active ? g_active : first_screen();
	focus_window(bw->w, !win_visible_on(bw, s));
}

static const struct swc_window_handler win_handler = {
	.destroy = on_win_destroy,
	.entered = on_win_entered,
};

static void
new_window(struct swc_window *w)
{
	struct blitz_win *bw;
	int32_t x = 0, y = 0;

	bw = calloc(1, sizeof(*bw));
	if (bw == NULL)
		return;
	bw->w = w;
	bw->fullscreen = false;
	wl_list_insert(&g_wins, &bw->link);
	swc_window_set_handler(w, &win_handler, bw);
	swc_window_set_stacked(w);
	swc_window_set_border(w, border_color_inactive, border_width, 0, 0);
	if (cursor_global(&x, &y))
		swc_window_set_position(w, x, y);
	swc_window_show(w);
	focus_window(w, true);
}

static void
on_screen_destroy(void *data)
{
	struct blitz_screen *s = data;

	if (s == NULL)
		return;
	wl_list_remove(&s->link);
	if (g_active == s)
		g_active = first_screen();
	free(s);
}

static void
on_screen_entered(void *data)
{
	struct blitz_screen *s = data;

	if (s != NULL)
		g_active = s;
}

static const struct swc_screen_handler screen_handler = {
	.destroy = on_screen_destroy,
	.entered = on_screen_entered,
};

static void
new_screen(struct swc_screen *s)
{
	struct blitz_screen *bs;

	bs = calloc(1, sizeof(*bs));
	if (bs == NULL)
		return;
	bs->s = s;
	wl_list_insert(&g_screens, &bs->link);
	swc_screen_set_handler(s, &screen_handler, bs);
	if (g_active == NULL)
		g_active = bs;
}

static const struct swc_manager manager = {
	.new_screen = new_screen,
	.new_window = new_window,
};

/* ------------------------------------------------------------------ */
/* wallpaper: in-process layer-shell client                            */
/*                                                                     */
/* Minimal hand-rolled zwlr_layer_shell_v1 (v1 wire subset) client     */
/* glue. The compositor end is neuswc's layer_shell (v5 server); we     */
/* bind at v1 and only use requests that exist since v1.               */
/* ------------------------------------------------------------------ */

static const struct wl_interface *bl_ls_types[] = { NULL, NULL, NULL, NULL };
static const struct wl_interface *bl_get_types[] = { NULL, NULL, NULL, NULL,
	NULL, NULL };

/* forward declarations (each references the other) */
static const struct wl_interface bl_layer_surface_iface;
static const struct wl_interface bl_layer_shell_iface;

static const struct wl_message bl_layer_shell_reqs[] = {
	{ "get_layer_surface", "noous", bl_get_types + 1 },
};

static const struct wl_message bl_layer_surface_reqs[] = {
	{ "set_size", "uu", bl_ls_types },
	{ "set_anchor", "u", bl_ls_types },
	{ "set_exclusive_zone", "i", bl_ls_types },
	{ "set_margin", "iiii", bl_ls_types },
	{ "set_keyboard_interactivity", "u", bl_ls_types },
	{ "ack_configure", "u", bl_ls_types + 3 },
	{ "destroy", "", bl_ls_types },
};

static const struct wl_message bl_layer_surface_evs[] = {
	{ "configure", "uuu", bl_ls_types },
	{ "closed", "", bl_ls_types },
};

static const struct wl_interface bl_layer_surface_iface = {
	"zwlr_layer_surface_v1",
	1,
	7,
	bl_layer_surface_reqs,
	2,
	bl_layer_surface_evs,
};

static const struct wl_interface bl_layer_shell_iface = {
	"zwlr_layer_shell_v1",
	1,
	1,
	bl_layer_shell_reqs,
	0,
	NULL,
};

struct wp_buf {
	struct wl_shm_pool *pool;
	struct wl_buffer *buf;
	void *map;
	size_t size;
};

struct wallpaper {
	struct wl_display *dpy;
	struct wl_registry *reg;
	struct wl_compositor *comp;
	struct wl_shm *shm;
	struct wl_proxy *shell;
	struct wl_proxy *lsurf;
	struct wl_surface *surf;
	struct wl_event_source *fdsrc;
	uint32_t pending_serial;
	bool have_configure;
	uint32_t width;
	uint32_t height;
	unsigned char *img;
	int img_w;
	int img_h;
};

static struct wallpaper g_wp;

static void
wp_buffer_release(void *data, struct wl_buffer *buf)
{
	struct wp_buf *wb = data;

	(void)buf;
	if (wb == NULL)
		return;
	wl_buffer_destroy(wb->buf);
	wl_shm_pool_destroy(wb->pool);
	munmap(wb->map, wb->size);
	free(wb);
}

static const struct wl_buffer_listener wp_buffer_listener = {
	.release = wp_buffer_release,
};

static int
wp_shm_fd(size_t size)
{
	const char *run = getenv("XDG_RUNTIME_DIR");
	char path[512];
	int fd;

	if (run == NULL)
		run = "/tmp";
	if (snprintf(path, sizeof(path), "%s/blitz-wp-XXXXXX", run) >=
	    (int)sizeof(path))
		return -1;
	fd = mkstemp(path);
	if (fd < 0)
		return -1;
	unlink(path);
	if (ftruncate(fd, (off_t)size) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

/* RGBA texel blended over 0xAARRGGBB background, result XRGB8888 */
static uint32_t
wp_blend(const unsigned char *px, uint32_t bg)
{
	uint32_t br = (bg >> 16) & 0xff, bgc = (bg >> 8) & 0xff,
	    bb = bg & 0xff;
	uint32_t a = px[3];

	if (a == 255)
		return ((uint32_t)px[0] << 16) | ((uint32_t)px[1] << 8) |
		    (uint32_t)px[2];
	if (a == 0)
		return (br << 16) | (bgc << 8) | bb;
	return ((((uint32_t)px[0] * a + br * (255 - a)) / 255) << 16) |
	    ((((uint32_t)px[1] * a + bgc * (255 - a)) / 255) << 8) |
	    (((uint32_t)px[2] * a + bb * (255 - a)) / 255);
}

static uint32_t
wp_sample_bilinear(const unsigned char *img, int iw, int ih, float sx,
    float sy, uint32_t bg)
{
	int x0 = (int)sx, y0 = (int)sy;
	int x1 = MIN(x0 + 1, iw - 1), y1 = MIN(y0 + 1, ih - 1);
	float fx = sx - (float)x0, fy = sy - (float)y0;
	unsigned char m[4];
	int c;

	x0 = MAX(x0, 0);
	y0 = MAX(y0, 0);
	for (c = 0; c < 4; c++) {
		float v = (float)img[(y0 * iw + x0) * 4 + c] * (1 - fx) *
		        (1 - fy) +
		    (float)img[(y0 * iw + x1) * 4 + c] * fx * (1 - fy) +
		    (float)img[(y1 * iw + x0) * 4 + c] * (1 - fx) * fy +
		    (float)img[(y1 * iw + x1) * 4 + c] * fx * fy;

		m[c] = (unsigned char)(v + 0.5f);
	}
	return wp_blend(m, bg);
}

static void
wp_render(uint32_t w, uint32_t h)
{
	int fd;
	void *map;
	size_t size;
	uint32_t stride = w * 4;
	struct wl_shm_pool *pool;
	struct wl_buffer *buf;
	struct wp_buf *wb;
	uint32_t *pix;
	uint32_t x, y;

	if (w == 0 || h == 0 || g_wp.shm == NULL || g_wp.surf == NULL)
		return;
	size = (size_t)stride * h;
	fd = wp_shm_fd(size);
	if (fd < 0)
		return;
	map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (map == MAP_FAILED) {
		close(fd);
		return;
	}
	pix = map;

	if (g_wp.img != NULL && wallpaper_mode == 2) {
		/* tile, unscaled */
		for (y = 0; y < h; y++) {
			for (x = 0; x < w; x++) {
				const unsigned char *px =
				    &g_wp.img[((y % (uint32_t)g_wp.img_h) *
				            g_wp.img_w +
				            (x % (uint32_t)g_wp.img_w)) *
				    4];

				pix[y * w + x] = wp_blend(px, background_color);
			}
		}
	} else if (g_wp.img != NULL) {
		/* fill (cover+crop) or fit (contain+letterbox) */
		float sw = (float)w / (float)g_wp.img_w;
		float sh = (float)h / (float)g_wp.img_h;
		float sc = wallpaper_mode == 0 ? MAX(sw, sh) : MIN(sw, sh);
		float ox = ((float)w - (float)g_wp.img_w * sc) * 0.5f;
		float oy = ((float)h - (float)g_wp.img_h * sc) * 0.5f;

		if (sc < 0.01f)
			sc = 0.01f;
		for (y = 0; y < h; y++) {
			for (x = 0; x < w; x++) {
				float sx = ((float)x - ox) / sc;
				float sy = ((float)y - oy) / sc;

				if (sx < 0 || sy < 0 || sx > (float)(g_wp.img_w - 1) ||
				    sy > (float)(g_wp.img_h - 1))
					pix[y * w + x] = background_color &
					    0x00ffffff;
				else
					pix[y * w + x] = wp_sample_bilinear(
					    g_wp.img, g_wp.img_w, g_wp.img_h, sx,
					    sy, background_color);
			}
		}
	} else {
		for (y = 0; y < h; y++)
			for (x = 0; x < w; x++)
				pix[y * w + x] = background_color & 0x00ffffff;
	}

	pool = wl_shm_create_pool(g_wp.shm, fd, (int32_t)size);
	close(fd);
	if (pool == NULL) {
		munmap(map, size);
		return;
	}
	buf = wl_shm_pool_create_buffer(pool, 0, (int32_t)w, (int32_t)h,
	    (int32_t)stride, WL_SHM_FORMAT_XRGB8888);
	if (buf == NULL) {
		wl_shm_pool_destroy(pool);
		munmap(map, size);
		return;
	}
	wb = calloc(1, sizeof(*wb));
	if (wb == NULL) {
		wl_buffer_destroy(buf);
		wl_shm_pool_destroy(pool);
		munmap(map, size);
		return;
	}
	wb->pool = pool;
	wb->buf = buf;
	wb->map = map;
	wb->size = size;
	wl_buffer_add_listener(buf, &wp_buffer_listener, wb);

	wl_surface_attach(g_wp.surf, buf, 0, 0);
	wl_surface_damage(g_wp.surf, 0, 0, (int32_t)w, (int32_t)h);
	wl_surface_commit(g_wp.surf);
	wl_display_flush(g_wp.dpy);
}

/* layer_surface.configure(serial, width, height) */
static void
wp_configure(void *data, struct wl_proxy *proxy, uint32_t serial, uint32_t w,
    uint32_t h)
{
	(void)data;
	(void)proxy;
	g_wp.pending_serial = serial;
	g_wp.have_configure = true;
	g_wp.width = w;
	g_wp.height = h;
	/* ack, then attach the wallpaper buffer */
	wl_proxy_marshal(g_wp.lsurf, 6, serial);
	if (g_wp.img == NULL && wallpaper[0] != '\0') {
		int iw = 0, ih = 0;

		g_wp.img = stbi_load(wallpaper, &iw, &ih, NULL, 4);
		if (g_wp.img != NULL) {
			g_wp.img_w = iw;
			g_wp.img_h = ih;
		} else {
			fprintf(stderr, "blitz: cannot load wallpaper '%s': %s\n",
			    wallpaper, stbi_failure_reason());
		}
	}
	wp_render(w, h);
}

static void
wp_closed(void *data, struct wl_proxy *proxy)
{
	(void)data;
	(void)proxy;
	g_wp.lsurf = NULL;
}

static const struct {
	void (*configure)(void *, struct wl_proxy *, uint32_t, uint32_t,
	    uint32_t);
	void (*closed)(void *, struct wl_proxy *);
} wp_lsurf_listener = { wp_configure, wp_closed };

static void
wp_global(void *data, struct wl_registry *reg, uint32_t name,
    const char *iface, uint32_t version)
{
	(void)data;
	if (strcmp(iface, "wl_compositor") == 0) {
		g_wp.comp = wl_registry_bind(reg, name, &wl_compositor_interface,
		    1);
	} else if (strcmp(iface, "wl_shm") == 0) {
		g_wp.shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
	} else if (strcmp(iface, "zwlr_layer_shell_v1") == 0) {
		g_wp.shell = wl_registry_bind(reg, name, &bl_layer_shell_iface,
		    MIN(version, 1));
	}
}

static void
wp_global_remove(void *data, struct wl_registry *reg, uint32_t name)
{
	(void)data;
	(void)reg;
	(void)name;
}

static const struct wl_registry_listener wp_reg_listener = {
	.global = wp_global,
	.global_remove = wp_global_remove,
};

static int
wp_dispatch(int fd, uint32_t mask, void *data)
{
	(void)fd;
	(void)data;
	if ((mask & WL_EVENT_READABLE) != 0)
		wl_display_dispatch(g_wp.dpy);
	return 0;
}

/* connected after the compositor socket exists; driven by its event loop */
static void
wallpaper_init(void)
{
	struct wl_region *region;

	memset(&g_wp, 0, sizeof(g_wp));
	g_wp.dpy = wl_display_connect(NULL);
	if (g_wp.dpy == NULL) {
		fprintf(stderr, "blitz: wallpaper: cannot connect (%s)\n",
		    wallpaper);
		return;
	}
	g_wp.reg = wl_display_get_registry(g_wp.dpy);
	wl_registry_add_listener(g_wp.reg, &wp_reg_listener, NULL);
	wl_display_roundtrip(g_wp.dpy);
	if (g_wp.comp == NULL || g_wp.shm == NULL || g_wp.shell == NULL) {
		fprintf(stderr, "blitz: wallpaper: missing globals\n");
		return;
	}
	g_wp.surf = wl_compositor_create_surface(g_wp.comp);
	if (g_wp.surf == NULL)
		return;
	/* clicks fall through to windows below */
	region = wl_compositor_create_region(g_wp.comp);
	if (region != NULL) {
		wl_surface_set_input_region(g_wp.surf, region);
		wl_region_destroy(region);
	}
	/* get_layer_surface(surface, output=NULL, layer=background, ns) */
	g_wp.lsurf = wl_proxy_marshal_constructor(g_wp.shell, 0,
	    &bl_layer_surface_iface, g_wp.surf, NULL, 0, "blitz-wallpaper");
	if (g_wp.lsurf == NULL)
		return;
	wl_proxy_add_listener(g_wp.lsurf, (void (**)(void))&wp_lsurf_listener,
	    NULL);
	wl_proxy_marshal(g_wp.lsurf, 1, 15u); /* anchor: all edges */
	wl_proxy_marshal(g_wp.lsurf, 2, -1); /* exclusive zone: stretch */
	wl_proxy_marshal(g_wp.lsurf, 0, 0u, 0u); /* size: compositor picks */
	wl_surface_commit(g_wp.surf);
	wl_display_flush(g_wp.dpy);
	g_wp.fdsrc = wl_event_loop_add_fd(g_loop, wl_display_get_fd(g_wp.dpy),
	    WL_EVENT_READABLE, wp_dispatch, NULL);
}

/* ------------------------------------------------------------------ */
/* main (mirrors hevel): display -> init -> binds -> socket -> run      */
/* ------------------------------------------------------------------ */

static void
on_signal(int s)
{
	(void)s;
	if (g_dpy != NULL)
		wl_display_terminate(g_dpy);
}

int
main(void)
{
	const char *sock;

	wl_list_init(&g_wins);
	wl_list_init(&g_screens);

	g_dpy = wl_display_create();
	if (g_dpy == NULL)
		die("wl_display_create failed");
	g_loop = wl_display_get_event_loop(g_dpy);
	if (!swc_initialize(g_dpy, g_loop, &manager))
		die("swc_initialize failed");

	setup_binds();

	sock = wl_display_add_socket_auto(g_dpy);
	if (sock == NULL)
		die("wl_display_add_socket_auto failed");
	setenv("WAYLAND_DISPLAY", sock, 1);

	wallpaper_init();

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	wl_display_run(g_dpy);

	if (g_wp.img != NULL)
		stbi_image_free(g_wp.img);
	if (g_wp.dpy != NULL)
		wl_display_disconnect(g_wp.dpy);
	swc_finalize();
	wl_display_destroy(g_dpy);
	return 0;
}
