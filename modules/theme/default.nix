{ config, lib, ... }:
let
  inherit (lib) types;
  base16Names = [
    "base00"
    "base01"
    "base02"
    "base03"
    "base04"
    "base05"
    "base06"
    "base07"
    "base08"
    "base09"
    "base0A"
    "base0B"
    "base0C"
    "base0D"
    "base0E"
    "base0F"
  ];
  requiredColors = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = types.strMatching "#[0-9A-Fa-f]{6}";
    }) base16Names
  );
  # A complete Base16 palette lets every consumer derive its own surface while
  # `palette` carries the semantic aliases that differ between themes.
  colorType = types.strMatching "#[0-9A-Fa-f]{6}";
  paletteType = types.submodule {
    options = {
      accent = lib.mkOption { type = colorType; };
      accentAlt = lib.mkOption { type = colorType; };
      background = lib.mkOption { type = colorType; };
      backgroundAlt = lib.mkOption { type = colorType; };
      foreground = lib.mkOption { type = colorType; };
      foregroundAlt = lib.mkOption { type = colorType; };
      border = lib.mkOption { type = colorType; };
      borderInactive = lib.mkOption { type = colorType; };
      error = lib.mkOption { type = colorType; };
      success = lib.mkOption { type = colorType; };
      warning = lib.mkOption { type = colorType; };
    };
  };
  glassType = types.submodule {
    options = {
      background = lib.mkOption { type = colorType; };
      backgroundSolid = lib.mkOption { type = colorType; };
      accent = lib.mkOption { type = colorType; };
      accentAlt = lib.mkOption { type = colorType; };
      textPrimary = lib.mkOption { type = colorType; };
      textSecondary = lib.mkOption { type = colorType; };
      separator = lib.mkOption { type = colorType; };
      separatorOpaque = lib.mkOption { type = colorType; };
      highlightOpacity = lib.mkOption { type = types.numbers.between 0.0 1.0; };
      innerStrokeOpacity = lib.mkOption { type = types.numbers.between 0.0 1.0; };
      borderOpacity = lib.mkOption { type = types.numbers.between 0.0 1.0; };
      shadowOpacity = lib.mkOption { type = types.numbers.between 0.0 1.0; };
      shadowRadius = lib.mkOption { type = types.ints.positive; };
      shadowOffsetY = lib.mkOption { type = types.ints.unsigned; };
      blurRadius = lib.mkOption { type = types.ints.positive; };
      cornerRadius = lib.mkOption { type = types.ints.positive; };
      cornerRadiusSmall = lib.mkOption { type = types.ints.positive; };
      padding = lib.mkOption { type = types.ints.positive; };
      itemSpacing = lib.mkOption { type = types.ints.positive; };
      fontSizeSmall = lib.mkOption { type = types.ints.positive; };
      fontSizeMedium = lib.mkOption { type = types.ints.positive; };
      fontSizeLarge = lib.mkOption { type = types.ints.positive; };
      fontSizeTitle = lib.mkOption { type = types.ints.positive; };
      animationDuration = lib.mkOption { type = types.ints.positive; };
      animationDurationSlow = lib.mkOption { type = types.ints.positive; };
    };
  };
  themeType = types.submodule {
    options = {
      name = lib.mkOption { type = types.str; };
      scheme = lib.mkOption { type = types.strMatching "[A-Za-z][A-Za-z0-9_-]*"; };
      type = lib.mkOption {
        type = types.enum [
          "dark"
          "light"
        ];
      };
      colors = lib.mkOption { type = types.submodule { options = requiredColors; }; };
      palette = lib.mkOption { type = paletteType; };
      glass = lib.mkOption { type = glassType; };
      settings = lib.mkOption {
        type = types.submodule {
          options = {
            font = lib.mkOption { type = types.str; };
            font-size = lib.mkOption { type = types.ints.positive; };
            blur = lib.mkOption { type = types.bool; };
            rounding = lib.mkOption { type = types.ints.unsigned; };
            opacity = lib.mkOption { type = types.numbers.between 0.0 1.0; };
            gaps-in = lib.mkOption { type = types.ints.unsigned; };
            gaps-out = lib.mkOption { type = types.ints.unsigned; };
            border-size = lib.mkOption { type = types.ints.unsigned; };
            system.font-size = lib.mkOption { type = types.ints.positive; };
          };
        };
      };
    };
  };
  defaultRegistry = import ./themes/cyberpunk-electric-dark.nix;
  mainThemeName = config.flake.mainThemeName;
  registry = defaultRegistry // config.flake.themeRegistry;
  mainTheme =
    registry.${mainThemeName} or (throw "modules/theme: main theme '${mainThemeName}' is not declared");
  colors =
    mainTheme.colors
    // mainTheme.palette
    // {
      accent-alt = mainTheme.palette.accentAlt;
      background-alt = mainTheme.palette.backgroundAlt;
      foreground-alt = mainTheme.palette.foregroundAlt;
      border-color = mainTheme.palette.border;
      border-color-inactive = mainTheme.palette.borderInactive;
    };
  theme = mainTheme.settings;

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

  hexToRgb =
    color:
    "${builtins.toString (extractChannel (stripHash color) 0)} ${builtins.toString (extractChannel (stripHash color) 2)} ${builtins.toString (extractChannel (stripHash color) 4)}";

  hexToCssRgba = color: opacity: "rgb(${hexToRgb color} / ${builtins.toString opacity})";

  hexToQmlRgba =
    color: opacity:
    let
      raw = stripHash color;
    in
    "Qt.rgba(${builtins.toString (extractChannel raw 0)} / 255, ${builtins.toString (extractChannel raw 2)} / 255, ${builtins.toString (extractChannel raw 4)} / 255, ${builtins.toString opacity})";

  colorsNoHash = builtins.mapAttrs (_: v: stripHash v) colors;
  colorsRgba = builtins.mapAttrs (_: v: hexToRgba (stripHash v) theme.opacity) colors;
  colorsRgbaValues = builtins.mapAttrs (_: v: hexToRgbaValues (stripHash v) theme.opacity) colors;
in
{
  options.flake = {
    themeRegistry = lib.mkOption {
      type = types.attrsOf themeType;
      default = { };
      description = "Typed colour, semantic, glass, and layout definitions available to this flake.";
    };
    mainThemeName = lib.mkOption {
      type = types.str;
      default = "cyberpunk-electric-dark";
      description = "Key of the active entry in flake.themeRegistry.";
    };
  };

  config = {
    flake = {
      inherit
        colors
        colorsNoHash
        colorsRgba
        colorsRgbaValues
        theme
        ;
      themes = {
        inherit
          mainTheme
          mainThemeName
          ;
        registry = registry;
        toRgb = hexToRgb;
        toRgba = hexToCssRgba;
        toQmlRgba = hexToQmlRgba;
      };
    };
  };
}
