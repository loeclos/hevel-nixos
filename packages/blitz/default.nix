{
  lib,
  writeText,
  writeShellScriptBin,
  symlinkJoin,
  stdenv,
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

    src = ./src;

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
in
symlinkJoin {
  pname = "blitz";
  inherit (unwrapped) version meta;
  paths = [
    unwrapped
    launcher
  ];
  passthru = {
    inherit unwrapped;
  };
}
