{
  lib,
  stdenv,
  fetchFromCodeberg,
  pkg-config,
  wayland,
  wayland-scanner,
  wayland-protocols,
}:
stdenv.mkDerivation {
  pname = "wawa";
  version = "1.0-unstable-2025-01-01";

  src = fetchFromCodeberg {
    owner = "sewn";
    repo = "wawa";
    rev = "ffc80332e377d4e1e73de9fede85a0e183455b25";
    hash = "sha256-SZoum6QcBp6uVaxHcpIVP74opH/qg+GGBb1A7cIimv8=";
  };

  strictDeps = true;
  __structuredAttrs = true;

  env.NIX_CFLAGS_COMPILE = "-Wno-incompatible-pointer-types";

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    wayland
    wayland-scanner
    wayland-protocols
  ];

  makeFlags = [
    "PREFIX=$(out)"
  ];

  meta = {
    description = "Simple wallpaper setter for wlr-layer-shell compositors";
    homepage = "https://codeberg.org/sewn/wawa";
    license = lib.licenses.mit;
    mainProgram = "wawa";
  };
}
