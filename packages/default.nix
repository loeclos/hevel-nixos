{ pkgs, lib }:
let
  scope = lib.makeScope pkgs.newScope (self: {
    neuwld = self.callPackage ./neuwld { };
    neuswc = self.callPackage ./neuswc { };
    hevel = self.callPackage ./hevel { };
    hst = self.callPackage ./hst { };
    neumenu = self.callPackage ./neumenu { };
    mojito = self.callPackage ./mojito { };
    wawa = self.callPackage ./wawa { };
    blitz = self.callPackage ./blitz { };
  });
in
{
  inherit (scope)
    neuwld
    neuswc
    hevel
    hst
    neumenu
    mojito
    wawa
    blitz
    ;
}
