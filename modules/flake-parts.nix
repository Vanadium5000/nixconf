{
  lib,
  inputs,
  ...
}:
{
  # Supported systems for your flake packages, shell, etc.
  config.systems = [
    "aarch64-linux"
    "i686-linux"
    "x86_64-linux"
    "aarch64-darwin"
    "x86_64-darwin"
  ];

  options.flake.diskoConfigurations = lib.mkOption {
    description = "Disko configurations for all hosts";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          disko.devices = lib.mkOption {
            description = "Disko device configuration";
            type = lib.types.attrs;
            default = { };
          };
        };
      }
    );
    default = { };
  };

  # Add the unstable pkgs to the global pkgs overlay
  config.perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.self.overlays.customPackages
          (final: prev: {
            unstable = import inputs.nixpkgs-unstable { inherit system; };
            nur = import inputs.nur {
              nurpkgs = prev;
              pkgs = prev;
            };
          })
        ];
      };
    };
}
