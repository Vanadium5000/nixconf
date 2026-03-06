{ pkgs ? import <nixpkgs> {} }:
let
  zshrc = pkgs.writeText "zshrc" ''
    alias cat="bat"
  '';
in
pkgs.mkShell {
  packages = [ pkgs.zsh pkgs.bat ];
  shellHook = ''
    ZDOTDIR=$PWD zsh
  '';
}
