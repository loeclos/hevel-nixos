{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.hevel;
  localPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};

  boolToC = b: if b then "true" else "false";

  # Built-in presets for terminals (handling hevel's execlp(term, term, term_flag, select_term_app_id, NULL) signature)
  terminalPresets = {
    foot = {
      package = pkgs.foot;
      cmd = "${pkgs.foot}/bin/foot";
      flag = "-a";
      selectAppId = "foot-select";
      appIds = [
        "foot"
        "foot-select"
        "st-wl"
        "ghostty"
        "alacritty"
      ];
    };
    ghostty = {
      package = pkgs.ghostty;
      # Ghostty only accepts --class=<value> as a single argument, whereas hevel passes
      # (term_flag, select_term_app_id) as two separate argv entries. Wrap it cleanly:
      cmd = "${pkgs.writeShellScript "hevel-ghostty" ''
        if [ "$1" = "--class" ] && [ -n "$2" ]; then
          shift
          APP_ID="$1"
          shift
          exec ${pkgs.ghostty}/bin/ghostty "--class=$APP_ID" "$@"
        fi
        exec ${pkgs.ghostty}/bin/ghostty "$@"
      ''}";
      flag = "--class";
      selectAppId = "com.mitchellh.ghostty.select";
      appIds = [
        "ghostty"
        "com.mitchellh.ghostty"
        "foot"
        "st-wl"
        "alacritty"
      ];
    };
    hst = {
      package = localPkgs.hst;
      cmd = "${localPkgs.hst}/bin/st-wl";
      flag = "-w";
      selectAppId = "st-wl-256color";
      appIds = [
        "st-wl"
        "foot"
        "havoc"
        "alacritty"
      ];
    };
  };

  preset = terminalPresets.${cfg.terminalPreset};

  cAppIds =
    (lib.concatMapStringsSep ", " (id: ''"${id}"'') cfg.settings.terminalAppIds) + ", NULL";

  generatedConfigH = pkgs.writeText "hevel-config.h" ''
    #ifndef CONFIG_H
    #define CONFIG_H

    #include <stdbool.h>
    #include <stddef.h>
    #include <stdint.h>

    static const uint32_t background_color = ${cfg.settings.colors.background};

    static const uint32_t outer_border_color_inactive = ${cfg.settings.colors.outerBorderInactive};
    static const uint32_t inner_border_color_inactive = ${cfg.settings.colors.innerBorderInactive};

    static const uint32_t outer_border_color_active = ${cfg.settings.colors.outerBorderActive};
    static const uint32_t inner_border_color_active = ${cfg.settings.colors.innerBorderActive};

    static const uint32_t outer_border_width = ${toString cfg.settings.border.outerWidth};
    static const uint32_t inner_border_width = ${toString cfg.settings.border.innerWidth};

    static const uint32_t select_box_color = ${cfg.settings.colors.selectBox};
    static const uint32_t select_box_border = ${toString cfg.settings.border.selectBox};

    static const char *const cursor_theme = "${cfg.settings.cursorTheme}";

    static const char *const select_term_app_id = "${cfg.settings.selectTermAppId}";
    static const char *const term = "${cfg.settings.term}";
    static const char *const term_flag = "${cfg.settings.termFlag}";

    static const bool enable_terminal_spawning = ${boolToC cfg.settings.enableTerminalSpawning};

    static const char *const terminal_app_ids[] = {${cAppIds}};

    static const int chord_click_timeout_ms = ${toString cfg.settings.chordClickTimeoutMs};

    static const int32_t move_scroll_edge_threshold = ${toString cfg.settings.scroll.moveEdgeThreshold};
    static const int32_t move_scroll_speed = ${toString cfg.settings.scroll.moveSpeed};
    static const float move_ease_factor = ${cfg.settings.scroll.moveEaseFactor};

    static const int timerms = ${toString cfg.settings.timerMs};

    static const int scrollpx = ${toString cfg.settings.scroll.px};
    static const int scrollease = ${toString cfg.settings.scroll.ease};
    static const int scrollcap = ${toString cfg.settings.scroll.cap};

    static const bool scroll_drag_mode = ${boolToC cfg.settings.scroll.dragMode};
    static const bool enable_zoom = ${boolToC cfg.settings.enableZoom};
    static const bool center_focus = ${boolToC cfg.settings.centerFocus};

    static const char *const custom_chord = "${cfg.settings.customChord}";

    ${cfg.extraConfig}

    #endif
  '';

  configuredPackage = cfg.basePackage.override {
    neuswc = cfg.neuswcPackage;
    conf = if cfg.configFile != null then cfg.configFile else generatedConfigH;
  };
in
{
  options.programs.hevel = {
    enable = lib.mkEnableOption "hevel, the scrollable Plan 9-inspired Wayland window manager";

    basePackage = lib.mkOption {
      type = lib.types.package;
      default = localPkgs.hevel;
      description = "Base hevel package to override with settings.";
    };

    neuswcPackage = lib.mkOption {
      type = lib.types.package;
      default = localPkgs.neuswc;
      description = "The neuswc package providing libswc and swc-launch.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = configuredPackage;
      description = "Final configured hevel package including hevel-launch.";
    };

    terminalPreset = lib.mkOption {
      type = lib.types.enum [
        "foot"
        "ghostty"
        "hst"
      ];
      default = "foot";
      description = ''
        Preconfigured terminal profile for hevel's 1->3 drag-to-spawn chord:
        - `foot` (Recommended): native wl_shm renderer, instant fork/exec, native `-a <id>` flag.
        - `ghostty`: wrapped so `--class=<id>` works with hevel's 2-arg execlp; heavier GTK4/EGL init.
        - `hst`: upstream's minimal neuwld-based st-wl fork (`-w <id>`).
      '';
    };

    terminalPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = preset.package;
      description = "Terminal package added to environment.systemPackages.";
    };

    installExtraUtils = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install neumenu alongside hevel.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional raw config.h path. If null, config.h is generated from `programs.hevel.settings`.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra C declarations appended before #endif in generated config.h.";
    };

    settings = {
      cursorTheme = lib.mkOption {
        type = lib.types.enum [
          "nein"
          "swc"
        ];
        default = "nein";
        description = ''Cursor theme: "nein" (Plan 9 cursors per chord) or "swc" (default cursor).'';
      };

      term = lib.mkOption {
        type = lib.types.str;
        default = preset.cmd;
        description = "Terminal executable or path spawned by the 1->3 drag chord.";
      };

      termFlag = lib.mkOption {
        type = lib.types.str;
        default = preset.flag;
        description = "CLI flag passed before selectTermAppId (e.g. `-a` for foot, `-w` for st-wl).";
      };

      selectTermAppId = lib.mkOption {
        type = lib.types.str;
        default = preset.selectAppId;
        description = "Wayland app_id matched by hevel to size the dragged terminal rectangle.";
      };

      enableTerminalSpawning = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Window swallowing: GUI programs launched from a terminal inherit its geometry.";
      };

      terminalAppIds = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = preset.appIds;
        description = "Substrings matched against window app_id/title for terminal window swallowing.";
      };

      customChord = lib.mkOption {
        type = lib.types.enum [
          "sticky"
          "fullscreen"
          "jump"
        ];
        default = "sticky";
        description = "Action bound to the 1->2 chord (sticky, fullscreen, or jump).";
      };

      enableZoom = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Allow scroll wheel to control canvas zoom while in drag scroll mode.";
      };

      centerFocus = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically center the focused window on the canvas.";
      };

      chordClickTimeoutMs = lib.mkOption {
        type = lib.types.int;
        default = 250;
        description = "Chord click timeout in milliseconds.";
      };

      timerMs = lib.mkOption {
        type = lib.types.int;
        default = 16;
        description = "Frame timer interval in milliseconds (~60Hz at 16ms).";
      };

      colors = {
        background = lib.mkOption {
          type = lib.types.str;
          default = "0xff777777";
          description = "Canvas background color (0xAARRGGBB).";
        };
        outerBorderInactive = lib.mkOption {
          type = lib.types.str;
          default = "0xffffffea";
          description = "Outer border color for inactive windows.";
        };
        innerBorderInactive = lib.mkOption {
          type = lib.types.str;
          default = "0xffddbd8c";
          description = "Inner border color for inactive windows.";
        };
        outerBorderActive = lib.mkOption {
          type = lib.types.str;
          default = "0xffffffea";
          description = "Outer border color for the focused window.";
        };
        innerBorderActive = lib.mkOption {
          type = lib.types.str;
          default = "0xffc99043";
          description = "Inner border color for the focused window.";
        };
        selectBox = lib.mkOption {
          type = lib.types.str;
          default = "0xffffffff";
          description = "Selection box border color when dragging a new terminal.";
        };
      };

      border = {
        outerWidth = lib.mkOption {
          type = lib.types.int;
          default = 4;
          description = "Outer window border width in pixels.";
        };
        innerWidth = lib.mkOption {
          type = lib.types.int;
          default = 4;
          description = "Inner window border width in pixels.";
        };
        selectBox = lib.mkOption {
          type = lib.types.int;
          default = 2;
          description = "Selection box border width in pixels.";
        };
      };

      scroll = {
        dragMode = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "True to drag mouse in all directions; false for vertical scroll wheel only.";
        };
        px = lib.mkOption {
          type = lib.types.int;
          default = 64;
          description = "Scroll step in pixels.";
        };
        ease = lib.mkOption {
          type = lib.types.int;
          default = 4;
          description = "Scroll easing divisor.";
        };
        cap = lib.mkOption {
          type = lib.types.int;
          default = 64;
          description = "Scroll speed cap.";
        };
        moveEdgeThreshold = lib.mkOption {
          type = lib.types.int;
          default = 80;
          description = "Distance from screen edge (px) that triggers edge-scrolling while moving a window.";
        };
        moveSpeed = lib.mkOption {
          type = lib.types.int;
          default = 16;
          description = "Edge-scroll speed while moving a window.";
        };
        moveEaseFactor = lib.mkOption {
          type = lib.types.str;
          default = "0.30f";
          description = "Float literal for window movement easing.";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Privilege wrapper: neuswc's swc-launch opens /dev/dri/*, /dev/input/*, and /dev/tty* directly
    # and drops privileges to the real UID before exec'ing hevel.
    security.wrappers.swc-launch = {
      source = "${cfg.neuswcPackage}/bin/swc-launch";
      owner = "root";
      group = "root";
      setuid = true;
    };

    environment.systemPackages =
      [
        configuredPackage
        cfg.neuswcPackage
      ]
      ++ lib.optional (cfg.terminalPackage != null) cfg.terminalPackage
      ++ lib.optional cfg.installExtraUtils localPkgs.neumenu;
  };
}
