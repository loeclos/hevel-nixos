{ pkgs, lib }:
let
  scope = lib.makeScope pkgs.newScope (self: {
    neuwld = self.callPackage ./neuwld { };
    neuswc = self.callPackage ./neuswc { };
    hevel = self.callPackage ./hevel { };
    hst = self.callPackage ./hst { };
    neumenu = self.callPackage ./neumenu { };
    wawa = self.callPackage ./wawa { };
  });
in
{
  inherit (scope)
    neuwld
    neuswc
    hevel
    hst
    neumenu
    wawa
    ;
}
