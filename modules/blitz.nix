{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.blitz;
  localPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};

  modConstant = {
    logo = "SWC_MOD_LOGO";
    alt = "SWC_MOD_ALT";
  };

  modMask =
    mods:
    lib.concatStringsSep " | " (
      map (
        m:
        if m == "mod" then
          "MOD"
        else if m == "shift" then
          "SWC_MOD_SHIFT"
        else if m == "ctrl" then
          "SWC_MOD_CTRL"
        else if m == "alt" then
          "SWC_MOD_ALT"
        else if m == "logo" then
          "SWC_MOD_LOGO"
        else
          throw "programs.blitz: unknown modifier ${m}"
      ) mods
    );

  cStrs = xs: "{ " + (lib.concatMapStringsSep ", " (s: ''"${s}"'') xs) + ", NULL }";

  # Extra SPAWN targets beyond term/menu get their own argv arrays.
  customSpawns = lib.filter (b: b.action == "SPAWN" && b.program == "custom") cfg.settings.binds;
  customSpawnArrays = lib.imap0 (
    i: b: "static const char *const blitz_spawn${toString i}[] = ${cStrs b.command};"
  ) customSpawns;

  bindRow = b: ''
    { ${modMask b.modifiers}, XKB_KEY_${b.key}, ${b.action}, ${
      if b.action != "SPAWN" then
        "NULL"
      else if b.program == "term" then
        "blitz_term"
      else if b.program == "menu" then
        "blitz_menu"
      else
        "blitz_spawn${toString b.customIndex}"
    } },'';

  bindsWithIndex =
    let
      go =
        ci: bs:
        if bs == [ ] then
          [ ]
        else
          let
            b = builtins.head bs;
          in
          [ (b // { customIndex = ci; }) ] ++ go (if b.action == "SPAWN" && b.program == "custom" then ci + 1 else ci) (builtins.tail bs);
    in
    go 0 cfg.settings.binds;

  generatedConfigH = pkgs.writeText "blitz-config.h" ''
    #ifndef BLITZ_CONFIG_H
    #define BLITZ_CONFIG_H

    #include <stdint.h>

    #include <swc.h>
    #include <xkbcommon/xkbcommon-keysyms.h>

    static const uint32_t blitz_mod = ${modConstant.${cfg.settings.mod}};
    #define MOD blitz_mod

    static const char *const blitz_term[] = ${cStrs cfg.settings.termCommand};
    static const char *const blitz_menu[] = ${cStrs cfg.settings.menuCommand};

    static const uint32_t border_width = ${toString cfg.settings.border.width};
    static const uint32_t border_color_active = ${cfg.settings.colors.active};
    static const uint32_t border_color_inactive = ${cfg.settings.colors.inactive};

    static const uint32_t background_color = ${cfg.settings.colors.background};

    static const char *const wallpaper = "${cfg.settings.wallpaper}";
    static const uint32_t wallpaper_mode = ${toString cfg.settings.wallpaperMode};

    static const int scroll_step = ${toString cfg.settings.scrollStep};
    static const float zoom_step = ${cfg.settings.zoomStep};

    ${lib.concatStringsSep "\n" customSpawnArrays}

    static const struct blitz_bind blitz_binds[] = {
    ${lib.concatStringsSep "\n" (map bindRow bindsWithIndex)}
    };

    #endif /* BLITZ_CONFIG_H */
  '';

  configuredPackage = cfg.basePackage.override {
    neuswc = cfg.neuswcPackage;
    conf = if cfg.configFile != null then cfg.configFile else generatedConfigH;
  };
in
{
  options.programs.blitz = {
    enable = lib.mkEnableOption "blitz, the keyboard-driven infinite-canvas Wayland compositor";

    basePackage = lib.mkOption {
      type = lib.types.package;
      default = localPkgs.blitz;
      description = "Base blitz package to override with settings.";
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
      description = "Final configured blitz package including blitz-launch.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Optional raw config.h path. If null, config.h is generated from `programs.blitz.settings`.";
    };

    settings = {
      mod = lib.mkOption {
        type = lib.types.enum [
          "logo"
          "alt"
        ];
        default = "logo";
        description = "Modifier key aliased as MOD in binds (Super or Alt).";
      };

      termCommand = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "hst" ];
        description = "Terminal argv spawned by the term bind.";
      };

      menuCommand = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "neumenu_run" ];
        description = "Menu argv spawned by the menu bind.";
      };

      binds = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              modifiers = lib.mkOption {
                type = lib.types.listOf (
                  lib.types.enum [
                    "mod"
                    "shift"
                    "ctrl"
                    "alt"
                    "logo"
                  ]
                );
                default = [ "mod" ];
              };
              key = lib.mkOption {
                type = lib.types.str;
                description = "Keysym name without the XKB_KEY_ prefix (e.g. Return, q, Tab).";
              };
              action = lib.mkOption {
                type = lib.types.enum [
                  "SPAWN"
                  "KILL"
                  "FULLSCREEN"
                  "ZOOM_IN"
                  "ZOOM_OUT"
                  "ZOOM_RESET"
                  "SCROLL_UP"
                  "SCROLL_DOWN"
                  "SCROLL_LEFT"
                  "SCROLL_RIGHT"
                  "CENTER"
                  "NEXT_FOCUS"
                  "QUIT"
                ];
              };
              program = lib.mkOption {
                type = lib.types.enum [
                  "term"
                  "menu"
                  "custom"
                ];
                default = "term";
                description = "For SPAWN: which argv array to launch.";
              };
              command = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "For SPAWN with program = custom: argv to launch.";
              };
            };
          }
        );
        default = [
          {
            modifiers = [ "mod" ];
            key = "Return";
            action = "SPAWN";
            program = "term";
          }
          {
            modifiers = [ "mod" ];
            key = "r";
            action = "SPAWN";
            program = "menu";
          }
          {
            modifiers = [ "mod" ];
            key = "q";
            action = "KILL";
          }
          {
            modifiers = [ "mod" ];
            key = "f";
            action = "FULLSCREEN";
          }
          {
            modifiers = [ "mod" ];
            key = "Left";
            action = "SCROLL_LEFT";
          }
          {
            modifiers = [ "mod" ];
            key = "Right";
            action = "SCROLL_RIGHT";
          }
          {
            modifiers = [ "mod" ];
            key = "Up";
            action = "SCROLL_UP";
          }
          {
            modifiers = [ "mod" ];
            key = "Down";
            action = "SCROLL_DOWN";
          }
          {
            modifiers = [ "mod" ];
            key = "period";
            action = "CENTER";
          }
          {
            modifiers = [ "mod" ];
            key = "Tab";
            action = "NEXT_FOCUS";
          }
          {
            modifiers = [ "mod" ];
            key = "equal";
            action = "ZOOM_IN";
          }
          {
            modifiers = [ "mod" ];
            key = "minus";
            action = "ZOOM_OUT";
          }
          {
            modifiers = [ "mod" ];
            key = "0";
            action = "ZOOM_RESET";
          }
          {
            modifiers = [
              "mod"
              "shift"
            ];
            key = "q";
            action = "QUIT";
          }
        ];
        description = "Keybind table rendered into the C bind array.";
      };

      border = {
        width = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Window border width in pixels.";
        };
      };

      colors = {
        background = lib.mkOption {
          type = lib.types.str;
          default = "0xff282828";
          description = "Flat canvas color (0xAARRGGBB) when no wallpaper is set.";
        };
        active = lib.mkOption {
          type = lib.types.str;
          default = "0xffff8c00";
          description = "Border color of the focused window.";
        };
        inactive = lib.mkOption {
          type = lib.types.str;
          default = "0xff3a3a3a";
          description = "Border color of unfocused windows.";
        };
      };

      wallpaper = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Absolute image path for the built-in wallpaper (empty disables it).";
      };

      wallpaperMode = lib.mkOption {
        type = lib.types.enum [
          0
          1
          2
        ];
        default = 0;
        description = "0 = fill, 1 = fit, 2 = tile.";
      };

      scrollStep = lib.mkOption {
        type = lib.types.int;
        default = 64;
        description = "Keyboard pan step in pixels per keypress.";
      };

      zoomStep = lib.mkOption {
        type = lib.types.str;
        default = "0.1f";
        description = "Float literal for the multiplicative zoom increment.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    security.wrappers.swc-launch = {
      source = "${cfg.neuswcPackage}/bin/swc-launch";
      owner = "root";
      group = "root";
      setuid = true;
    };

    environment.systemPackages = [
      configuredPackage
      cfg.neuswcPackage
      localPkgs.hst
      localPkgs.neumenu
    ];
  };
}
