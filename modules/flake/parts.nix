{
  lib,
  inputs,
  self,
  config,
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

  options.flake.temporaryNixpkgsOverrides = lib.mkOption {
    description = "Temporary package overrides with built-in expiry checks.";
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = self.lib.nixpkgs.temporaryOverrideModule;
      }
    );
    default = self.lib.nixpkgs.temporaryOverrides;
  };

  config.perSystem =
    { system, ... }:
    {
      _module.args.pkgs = self.lib.nixpkgs.mkPkgs {
        inherit inputs self system;
        temporaryOverrides = config.flake.temporaryNixpkgsOverrides;
        extraPythonOverrides = _python-final: python-prev: {
          mcp = python-prev.mcp.overridePythonAttrs (_old: {
            # Disable flaky SSE/HTTP server tests (ClosedResourceError, server startup timeouts)
            # that fail in the Nix sandbox due to async race conditions.
            doCheck = false;
          });
        };
      };

      apps = {
        rebuild = {
          type = "app";
          program = "${self.packages.${system}.rebuild}/bin/rebuild";
        };
      };
    };
}
