# This file describes your repository contents.
# It should return a set of nix derivations
# and optionally the special attributes `lib`, `modules` and `overlays`.
# It should NOT import <nixpkgs>. Instead, you should take pkgs as an argument.
# Having pkgs default to <nixpkgs> is fine though, and it lets you use short
# commands such as:
#     nix-build -A mypackage

{ pkgs ? import <nixpkgs> {}
, fromFlake ? false
, ...
}@args:


let
  dummyPackage = pkgs.hello;
in
with pkgs;
{
  # The `lib`, `modules`, and `overlay` names are special
  lib = import ./lib { inherit pkgs; }; # functions # FIXME properly extend lib here
  modules = import ./modules; # NixOS modules
  overlays = import ./overlays; # nixpkgs overlays

  pam-impermanence = pkgs.callPackage ./pkgs/pam-impermanence { pam = pkgs.pam; };
  # this builds all but installs only altered pam_unix
  # TODO: build only what's neded
  pam-impermalite = callPackage ./pkgs/pam-impermalite { inherit pam; };

  vscode-insiders = callPackage ./pkgs/vscode-insiders {
    inherit pkgs;
  };

  simple-time-tracker = callPackage ./pkgs/simple-time-tracker {
    inherit (pkgs) stdenv buildNpmPackage fetchFromGitHub electron lib makeWrapper makeDesktopItem;
  };

  betterbird-mac = callPackage ./pkgs/betterbird-mac { inherit pkgs; };

  opensmtpd-filters = callPackage ./pkgs/opensmtpd-filters pkgs;

  manage = callPackage ./pkgs/manage pkgs;

  s-mailx = callPackage ./pkgs/s-mailx pkgs;

}
