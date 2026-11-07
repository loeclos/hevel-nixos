# Drop-in example for your NixOS configuration (e.g. inside rebuild/ or ~/.dotfiles)
{
  # 1. In your system flake.nix inputs:
  # inputs.hevel-nixos = {
  #   url = "path:/home/loeclos/Projects/hevel-nixos";
  #   inputs.nixpkgs.follows = "nixpkgs";
  # };
  #
  # 2. In your nixosSystem modules list:
  # inputs.hevel-nixos.nixosModules.default

  programs.hevel = {
    enable = true;

    # Choose between "foot" (recommended), "ghostty", or "hst" (upstream st-wl fork)
    terminalPreset = "foot";

    # Compile-time config.h options exposed as Nix options:
    settings = {
      cursorTheme = "nein";
      customChord = "sticky"; # "sticky" | "fullscreen" | "jump"
      enableZoom = true;
      centerFocus = true;
      enableTerminalSpawning = true;

      scroll = {
        dragMode = true;
        px = 64;
        ease = 4;
        cap = 64;
      };

      colors = {
        background = "0xff777777";
        outerBorderInactive = "0xffffffea";
        innerBorderInactive = "0xffddbd8c";
        outerBorderActive = "0xffffffea";
        innerBorderActive = "0xffc99043";
        selectBox = "0xffffffff";
      };
    };
  };
}
