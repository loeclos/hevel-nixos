{
  lib,
  meson,
  pkg-config,
  wayland-scanner,
  doxygen,
  ninja,
  fontconfig,
  pixman,
  freetype,
  libdrm,
  wayland,
  stdenv,
  fetchgit,
  drmSupport ? true,
  waylandSupport ? true,
  documentationSupport ? false,
}:
stdenv.mkDerivation {
  pname = "neuwld";
  version = "0-unstable-2026-09-01";

  src = fetchgit {
    url = "https://srcdump.net/shrub/neuwld.git";
    rev = "554f827cadfdfcc276c709dbffa3b2b04c70cf7c";
    hash = "sha256-KAK4/TpNekaonN0yxi4/5mRdZL1uxYdGmwl41FRH5wU=";
  };

  strictDeps = true;
  __structuredAttrs = true;

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
  ]
  ++ lib.optional (waylandSupport && drmSupport) wayland-scanner
  ++ lib.optional documentationSupport doxygen;

  buildInputs = [
    fontconfig
    pixman
    freetype
  ]
  ++ lib.optional drmSupport libdrm
  ++ lib.optional waylandSupport wayland;

  mesonAutoFeatures = "auto";

  mesonFlags = [
    (lib.mesonEnable "wayland" waylandSupport)
    (lib.mesonEnable "drm" drmSupport)
    (lib.mesonEnable "doxygen" documentationSupport)
  ];

  meta = {
    description = "Drawing library that targets Wayland (neulibs fork of wld)";
    platforms = lib.platforms.unix;
    homepage = "https://git.sr.ht/~shrub900/neuwld";
    license = lib.licenses.mit;
  };
}
