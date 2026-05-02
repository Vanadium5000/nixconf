{
  lib,
  inputs,
  self,
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
        config = {
          # HACK: this sucks
          allowUnfree = true;
          # CVE-2024-23342: ecdsa timing side-channel attack allowing private key recovery.
          # Required by electrum-ltc (litecoin-wallet). Low-value wallet, acceptable risk.
          permittedInsecurePackages = [
            "python3.13-ecdsa-0.19.1"
          ];
        };
        overlays = [
          (self.lib.nixpkgs.mkSharedOverlay {
            inherit inputs self system;
            extraPythonOverrides = _python-final: python-prev: {
              mcp = python-prev.mcp.overridePythonAttrs (_old: {
                # Disable flaky SSE/HTTP server tests (ClosedResourceError, server startup timeouts)
                # that fail in the Nix sandbox due to async race conditions.
                doCheck = false;
              });
            };
          })
          inputs.nix4vscode.overlays.default
        ];
      };

      apps = {
        rebuild = {
          type = "app";
          program = "${self.packages.${system}.rebuild}/bin/rebuild";
        };
      };
    };
}
