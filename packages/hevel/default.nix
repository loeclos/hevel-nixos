{
  lib,
  writeText,
  writeShellScriptBin,
  symlinkJoin,
  stdenv,
  fetchFromSourcehut,
  neuswc,
  pkg-config,
  wayland,
  libxkbcommon,
  conf ? null,
  swcLaunchPath ? "${neuswc}/bin/swc-launch",
}:
let
  unwrapped = stdenv.mkDerivation {
    pname = "hevel-unwrapped";
    version = "0-unstable-2026-05-01";

    src = fetchFromSourcehut {
      owner = "~dlm";
      repo = "hevel";
      rev = "7ef61a5c0d4012417443734919ac723635cd5464";
      hash = "sha256-ad4euUV+jJYG58aO9tfKyCq8sznDf2tHj7RmORqnP1o=";
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
    ];

    makeFlags = [
      "PREFIX=$(out)"
    ];

    postPatch =
      let
        configFile =
          if lib.isDerivation conf || builtins.isPath conf then conf else writeText "config.h" conf;
      in
      lib.optionalString (conf != null) "cp ${configFile} config.h";

    meta = {
      description = "Scrollable, floating window manager for Wayland that uses mouse chords for all commands";
      homepage = "https://git.sr.ht/~dlm/hevel";
      license = lib.licenses.isc;
      mainProgram = "hevel";
      platforms = lib.platforms.unix;
    };
  };

  launcher = writeShellScriptBin "hevel-launch" ''
    # Look for NixOS setuid wrapper first so GDM/SDDM/unprivileged users can open DRM & VT
    if [ -x /run/wrappers/bin/swc-launch ]; then
      SWC_LAUNCH=/run/wrappers/bin/swc-launch
    else
      SWC_LAUNCH="${swcLaunchPath}"
    fi
    exec "$SWC_LAUNCH" "${unwrapped}/bin/hevel" "$@"
  '';

  desktopItem = writeText "hevel.desktop" ''
    [Desktop Entry]
    Name=Hevel
    Comment=Scrollable, floating Plan 9-inspired Wayland window manager
    Exec=${launcher}/bin/hevel-launch
    Type=Application
    DesktopNames=hevel
  '';
in
symlinkJoin {
  pname = "hevel";
  inherit (unwrapped) version meta;
  paths = [
    unwrapped
    launcher
  ];
  postBuild = ''
    mkdir -p $out/share/wayland-sessions
    ln -s ${desktopItem} $out/share/wayland-sessions/hevel.desktop
  '';
  passthru = {
    inherit unwrapped;
    providedSessions = [ "hevel" ];
  };
}
