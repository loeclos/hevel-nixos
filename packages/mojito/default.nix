{
  lib,
  fetchFromSourcehut,
  stdenv,
  pkg-config,
  wayland,
  wayland-scanner,
  wayland-protocols,
  pixman,
  libdrm,
  fontconfig,
  neuwld,
  neuswc,
}:
stdenv.mkDerivation {
  pname = "mojito";
  version = "0-unstable-2026-09-01";

  src = fetchFromSourcehut {
    owner = "~dlm";
    repo = "mojito";
    rev = "5e6a307ec812ce6d7ecd66916cf4658afb19420e";
    hash = "sha256-wEggHpGKpR9oJvRVbyYeqjO683XaOL47czHGqPSoXKo=";
  };

  strictDeps = true;
  __structuredAttrs = true;

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
  ];

  buildInputs = [
    pixman
    wayland
    wayland-protocols
    libdrm
    fontconfig
    neuwld
    neuswc
  ];

  makeFlags = [
    "PREFIX=$(out)"
  ];

  meta = {
    description = "Featherweight lemonbar-compatible status bar for Wayland";
    homepage = "https://git.sr.ht/~dlm/mojito";
    license = lib.licenses.isc;
    mainProgram = "mojito";
    platforms = lib.platforms.linux;
  };
}
