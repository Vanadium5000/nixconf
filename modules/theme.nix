{ lib, ... }:
let
  # Nix Cyberpunk Electric Dark
  colors = {
    base00 = "#000000"; # black
    base01 = "#0d0d0d"; # darkish black
    base02 = "#383838"; # brightish black
    base03 = "#545454"; # bright black
    base04 = "#7e7e7e"; # darker white
    base05 = "#a8a8a8"; # white
    base06 = "#d2d2d2"; # middle white
    base07 = "#fcfcfc"; # bright white
    base08 = "#fc5454"; # bright red
    base09 = "#a85400"; # yellow
    base0A = "#fcfc54"; # bright yellow
    base0B = "#54fc54"; # bright green
    base0C = "#54fcfc"; # bright cyan
    base0D = "#5454fc"; # bright blue
    base0E = "#fc54fc"; # bright magenta
    base0F = "#00a800"; # green

    accent = colors.base0D;
    accent-alt = colors.base0C;
    background = colors.base00;
    background-alt = colors.base01;
    foreground = colors.base05;
    foreground-alt = colors.base06;
    border-color = colors.base0D;
    border-color-inactive = colors.base03;
  };

  theme = {
    font = "JetBrainsMono Nerd Font";
    blur = true;
    rounding = 8;
    opacity = 0.9;
    gaps-in = 2; # between windows/buttons
    gaps-out = 3; # between windows and border of display
    border-size = 1;
    font-size = 13;
    system.font-size = 11;
  };

  hexDigits = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    "a" = 10;
    "b" = 11;
    "c" = 12;
    "d" = 13;
    "e" = 14;
    "f" = 15;
    "A" = 10;
    "B" = 11;
    "C" = 12;
    "D" = 13;
    "E" = 14;
    "F" = 15;
  };

  hexToInt =
    hex:
    lib.lists.foldl' (acc: digit: acc * 16 + (hexDigits.${digit} or 0)) 0 (
      lib.strings.stringToCharacters hex
    );

  extractChannel = color: pos: hexToInt (lib.strings.substring pos 2 color);

  hexToRgba =
    color: opacity:
    let
      r = extractChannel color 0;
      g = extractChannel color 2;
      b = extractChannel color 4;
    in
    "rgba(${builtins.toString r},${builtins.toString g},${builtins.toString b},${builtins.toString opacity})";

  hexToRgbaValues =
    color: opacity:
    let
      r = extractChannel color 0;
      g = extractChannel color 2;
      b = extractChannel color 4;
    in
    [
      r
      g
      b
      opacity
    ];

  stripHash =
    str:
    if builtins.substring 0 1 str == "#" then
      builtins.substring 1 (builtins.stringLength str - 1) str
    else
      str;

  colorsNoHash = builtins.mapAttrs (_: v: stripHash v) colors;
  colorsRgba = builtins.mapAttrs (_: v: hexToRgba (stripHash v) theme.opacity) colors;
  colorsRgbaValues = builtins.mapAttrs (_: v: hexToRgbaValues (stripHash v) theme.opacity) colors;
in
{
  flake = {
    inherit
      colors
      colorsNoHash
      colorsRgba
      colorsRgbaValues
      theme
      ;
  };
}
