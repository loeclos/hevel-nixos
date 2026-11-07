> This repo is fully AI generated. Nothing is guaranteed to work. Use common sense. The owner uses this for personal purposes, and doesn't care about the quality of the code.

# hevel-nixos

Local NixOS flake packaging [`hevel`](https://sr.ht/~dlm/hevel/) and its `neulibs` dependencies (`neuwld`, `neuswc`, `hst`, `neumenu`), plus a complete `programs.hevel` NixOS module with GDM/SDDM session integration and Nix-native `config.h` options.

## What's Inside

- `packages/neuwld` — Wayland drawing library (`wld` fork)
- `packages/neuswc` — Wayland compositor library (`swc` fork) + `swc-launch`
- `packages/hevel` — `hevel` + `hevel-launch` wrapper + `share/wayland-sessions/hevel.desktop`
- `packages/hst` — `st-wl` fork built on `neuwld`
- `packages/neumenu` — dynamic Wayland menu built on `neuwld`/`neuswc`
- `modules/hevel.nix` — `programs.hevel` NixOS module:
  - Creates `/run/wrappers/bin/swc-launch` via `security.wrappers.swc-launch` (setuid root, required because `neuswc` opens `/dev/dri/*`, `/dev/input/*`, and VTs directly without `logind`/`libseat` and drops privileges before spawning `hevel`)
  - Registers `hevel.desktop` in `services.displayManager.sessionPackages` for GDM/SDDM
  - Generates `config.h` directly from `programs.hevel.settings.*`
- `hosts/example.nix` — ready-to-import NixOS configuration snippet

## `foot` vs `ghostty` on Hevel

Hevel spawns terminals on the `1 -> 3` drag chord using:

```c
execlp(term, term, term_flag, select_term_app_id, NULL);
```

And sizes the dragged rectangle when a Wayland surface appears with `app_id == select_term_app_id`.

| Criteria | `foot` (`terminalPreset = "foot"`, default) | `ghostty` (`terminalPreset = "ghostty"`) |
|---|---|---|
| **CLI flag compatibility** | Native: `foot -a foot-select` takes 2 separate args out of the box | Needs wrapper: `ghostty` only parses `--class=<id>` as a single arg (handled automatically by `terminalPreset = "ghostty"`) |
| **Rendering protocol** | `wl_shm` (CPU/Pixman shared memory) — matches `neuswc`/`neuwld`'s software/DRM design | GTK4 + OpenGL/EGL (`zwp_linux_dmabuf_v1` v3) — `neuswc` only advertises `XRGB8888`/`ARGB8888` single-plane dmabuf |
| **Cold spawn speed (`fork`+`exec` per rectangle)** | ~15–25 ms per dragged window | ~150–300 ms per cold GTK4/GPU init |
| **Window swallowing (`enable_terminal_spawning`)** | Direct PID tree walk works cleanly | Works when launched as standalone processes |
| **Verdict** | **Recommended default** | Supported via `terminalPreset = "ghostty"` |
