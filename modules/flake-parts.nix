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
          # CVE-2024-23342: ecdsa timing side-channel attack allowing private key recovery.
          # Required by electrum-ltc (litecoin-wallet). Low-value wallet, acceptable risk.
          permittedInsecurePackages = [
            "python3.13-ecdsa-0.19.1"
          ];
        };
        overlays = [
          (final: prev: {
            customPackages = self.packages.${system};
            unstable = import inputs.nixpkgs-unstable {
              inherit system;
            };
            nur = import inputs.nur {
              nurpkgs = prev;
              pkgs = prev;
            };
            pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
              (python-final: python-prev: {
                tenacity = python-prev.tenacity.overridePythonAttrs (old: {
                  # Disable flaky tests (AssertionError: 4 not less than 1.1)
                  # Fixes build failures when system is under load
                  doCheck = false;
                });
                trezor = python-prev.trezor.overridePythonAttrs (old: {
                  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ python-final.pythonRelaxDepsHook ];

                  # Trezor 0.20.0 tightened wheel metadata to keyring>=25.7.0, but nixpkgs still
                  # ships 25.6.0 here. Relax the lower bound locally so electrum-ltc keeps building
                  # until nixpkgs catches up. Source: trezor-firmware/python/pyproject.toml.
                  pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "keyring" ];
                });
              })
            ];
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
