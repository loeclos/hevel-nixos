{
  description = "NixOS port & module for hevel (Plan 9-inspired Wayland window manager) and neulibs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      overlays.default =
        final: prev:
        import ./packages {
          pkgs = final;
          inherit (final) lib;
        };

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system}.extend self.overlays.default;
        in
        import ./packages {
          inherit pkgs;
          inherit (pkgs) lib;
        }
      );

      nixosModules = {
        hevel = import ./modules/hevel.nix { inherit self; };
        default = self.nixosModules.hevel;
      };

      checks = forAllSystems (
        system:
        let
          pkgs = self.packages.${system};
        in
        {
          inherit (pkgs)
            neuwld
            neuswc
            hevel
            hst
            neumenu
            ;
        }
      );
    };
}
