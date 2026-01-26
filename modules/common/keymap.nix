{
  flake.nixosModules.common =
    {
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib) types mkOption;

      # A keybind leaf can have: exec, package, and optionally description
      keybindLeafType = types.submodule {
        options = {
          exec = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Command to execute";
          };
          package = mkOption {
            type = types.nullOr types.package;
            default = null;
            description = "Package to run (uses getExe)";
          };
          description = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Human-readable description of what this keybind does";
          };
        };
      };

      # Recursive type: either a leaf node or nested keybinds
      keymapType = types.lazyAttrsOf (
        types.either keybindLeafType (types.lazyAttrsOf types.unspecified)
      );
    in
    {
      options.preferences = {
        keymap = mkOption {
          type = keymapType;
          default = { };
          description = ''
            Keybind configuration supporting nested keychords.
            Each leaf node can have:
            - exec: Command string to execute
            - package: Package to run via getExe
            - description: Human-readable description for help display
          '';
          example = {
            "SUPER + d" = {
              "f" = {
                exec = "firefox";
                description = "Launch Firefox browser";
              };
            };
            "SUPER + a" = {
              "b"."c" = {
                exec = "pcmanfm";
                description = "Open file manager";
              };
            };
            "a" = {
              package = pkgs.firefox;
              description = "Launch Firefox";
            };
          };
        };
      };
    };
}
