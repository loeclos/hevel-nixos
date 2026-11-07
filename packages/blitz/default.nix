{
  lib,
  writeText,
  writeShellScriptBin,
  symlinkJoin,
  stdenv,
  fetchFromGitHub,
  neuswc,
  pkg-config,
  wayland,
  libxkbcommon,
  stb,
  conf ? null,
  swcLaunchPath ? "${neuswc}/bin/swc-launch",
}:
let
  unwrapped = stdenv.mkDerivation {
    pname = "blitz-unwrapped";
    version = "0-unstable-2026-11-07";

    src = fetchFromGitHub {
      owner = "loeclos";
      repo = "blitz";
      rev = "815883d853555d395b151c7e0a3346725f16f4ca";
      hash = "sha256-cDPGsY8AfnNlEYQHqPZx9OKlBg9L+IrftMqEitVGHTs=";
    };

    strictDeps = true;
    __structuredAttrs = true;

    nativeBuildInputs = [
      pkg-config
    ];

    buildInputs = [
      neuswc
      wayland
      libxkbcommon
      stb
    ];

    # stb_image.h lives in <stb>/include/stb/
    env.NIX_CFLAGS_COMPILE = "-I${lib.getDev stb}/include/stb";

    makeFlags = [
      "PREFIX=$(out)"
    ];

    # The unwrapped bin dir is all we need from `make install`; the desktop
    # entry is regenerated at the top level (pointed at blitz-launch).
    postInstall = ''
      rm $out/share/wayland-sessions/blitz.desktop
    '';

    postPatch =
      let
        configFile =
          if lib.isDerivation conf || builtins.isPath conf then conf else writeText "config.h" conf;
      in
      lib.optionalString (conf != null) "cp ${configFile} config.h";

    meta = {
      description = "Keyboard-driven infinite-canvas Wayland compositor on neuswc";
      homepage = "https://github.com/loeclos/hevel-nixos";
      license = lib.licenses.mit;
      mainProgram = "blitz";
      platforms = lib.platforms.linux;
    };
  };

  launcher = writeShellScriptBin "blitz-launch" ''
    if [ -x /run/wrappers/bin/swc-launch ]; then
      SWC_LAUNCH=/run/wrappers/bin/swc-launch
    else
      SWC_LAUNCH="${swcLaunchPath}"
    fi
    exec "$SWC_LAUNCH" "${unwrapped}/bin/blitz" "$@"
  '';

  # uwsm (and display managers) resolve share/wayland-sessions/blitz.desktop.
  # Upstream Exec=blitz would bypass the setuid swc-launch wrapper, so ship
  # our own entry pointed at blitz-launch (the unwrapped derivation's copy
  # installed by `make install` is removed in postInstall below).
  desktopItem = writeText "blitz.desktop" ''
    [Desktop Entry]
    Name=blitz
    Comment=Keyboard-driven infinite-canvas Wayland compositor
    Exec=${launcher}/bin/blitz-launch
    Type=Application
    DesktopNames=blitz
  '';
in
symlinkJoin {
  pname = "blitz";
  inherit (unwrapped) version meta;
  paths = [
    unwrapped
    launcher
  ];
  postBuild = ''
    mkdir -p $out/share/wayland-sessions
    ln -s ${desktopItem} $out/share/wayland-sessions/blitz.desktop
  '';
  passthru = {
    inherit unwrapped;
  };
}
