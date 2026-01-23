{ lib, ... }:
let
  # ===========================================================================
  # Nix Cyberpunk Electric Dark - Application Theme
  # Used for terminal applications, syntax highlighting, and app-specific styling
  # ===========================================================================
  colors = {
    base00 = "#000000"; # black (background)
    base01 = "#0d0d0d"; # darkish black (lighter background)
    base02 = "#383838"; # brightish black (selection)
    base03 = "#545454"; # bright black (comments)
    base04 = "#7e7e7e"; # darker white (dark foreground)
    base05 = "#a8a8a8"; # white (default foreground)
    base06 = "#d2d2d2"; # middle white (light foreground)
    base07 = "#fcfcfc"; # bright white (lightest)
    base08 = "#fc5454"; # bright red
    base09 = "#a85400"; # orange/yellow
    base0A = "#fcfc54"; # bright yellow
    base0B = "#54fc54"; # bright green
    base0C = "#54fcfc"; # bright cyan
    base0D = "#5454fc"; # bright blue
    base0E = "#fc54fc"; # bright magenta
    base0F = "#00a800"; # dark green

    # Semantic aliases
    accent = colors.base0D;
    accent-alt = colors.base0C;
    background = colors.base00;
    background-alt = colors.base01;
    foreground = colors.base05;
    foreground-alt = colors.base06;
    border-color = colors.base0D;
    border-color-inactive = colors.base03;
  };

  # ===========================================================================
  # Apple Liquid Glass UI Theme
  # Official dark mode values from iOS 26 / macOS Tahoe (WWDC25)
  # Used for shell UI components (menus, panels, overlays)
  # ===========================================================================
  liquidGlass = {
    # Colors - Apple Dark Mode System Colors
    background = "rgba(15, 15, 23, 0.78)"; # Translucent dark glass
    backgroundSolid = "#1C1C1E"; # Solid fallback
    accent = "#0A84FF"; # iOS system blue (dark mode)
    accentAlt = "#64D2FF"; # iOS system cyan (dark mode)

    # Text hierarchy (Apple HIG)
    textPrimary = "#FFFFFF";
    textSecondary = "#EBEBF5";
    textTertiary = "rgba(235, 235, 245, 0.3)";

    # Separators
    separator = "rgba(84, 84, 88, 0.65)";
    separatorOpaque = "#38383A";

    # Glass material properties
    highlightOpacity = 0.15; # Top specular reflection
    innerStrokeOpacity = 0.06; # Cut-glass edge effect
    borderOpacity = 0.28; # Accent border visibility
    borderWidth = 1;

    # Shadow (Apple design tokens)
    shadowOpacity = 0.45;
    shadowRadius = 20;
    shadowOffsetY = 6;

    # Backdrop blur
    blurRadius = 40;

    # Layout tokens
    cornerRadius = 22; # Large panels
    cornerRadiusSmall = 12; # Buttons, items
    padding = 14;
    itemSpacing = 10;

    # Typography
    fontFamily = "JetBrainsMono Nerd Font";
    fontSizeSmall = 11;
    fontSizeMedium = 14;
    fontSizeLarge = 17;
    fontSizeTitle = 22;

    # Animation
    animationDuration = 150; # ms
    animationDurationSlow = 250; # ms
  };

  # ===========================================================================
  # General Theme Settings
  # ===========================================================================
  theme = {
    font = "JetBrainsMono Nerd Font";
    blur = true;
    rounding = 8;
    opacity = 1.0;
    gaps-in = 2; # Between windows/buttons
    gaps-out = 4; # Between windows and display edge
    border-size = 1;
    font-size = 11;
    system.font-size = 11;

    # Liquid Glass reference (for modules that need it)
    liquid = liquidGlass;
  };

  # ===========================================================================
  # Color Conversion Utilities
  # ===========================================================================
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
      liquidGlass
      ;
  };
}
