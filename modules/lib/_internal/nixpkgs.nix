{ lib, ... }:
{
  mkSharedOverlay =
    {
      inputs,
      self,
      system ? null,
      unstableConfig ? null,
      extraPythonOverrides ? (_python-final: _python-prev: { }),
    }:
    final: prev:
    let
      overlaySystem = if system == null then final.stdenv.hostPlatform.system else system;
    in
    {
      customPackages = self.packages.${overlaySystem};
      unstable = import inputs.nixpkgs-unstable (
        {
          system = overlaySystem;
        }
        // lib.optionalAttrs (unstableConfig != null) {
          # NixOS hosts pass final.config so pkgs.unstable observes the same nixpkgs
          # package policy as the system package set; flake-parts omits this to keep
          # its per-system package import behavior unchanged.
          config = unstableConfig;
        }
      );
      nur = import inputs.nur {
        nurpkgs = prev;
        pkgs = prev;
      };
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (
          python-final: python-prev:
          {
            tenacity = python-prev.tenacity.overridePythonAttrs (_old: {
              # Disable flaky tests (AssertionError: 4 not less than 1.1)
              # Fixes build failures when system is under load.
              doCheck = false;
            });
            trezor = python-prev.trezor.overridePythonAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ python-final.pythonRelaxDepsHook ];

              # Trezor 0.20.0 tightened wheel metadata to keyring>=25.7.0, but nixpkgs still
              # ships 25.6.0 here. Relax the lower bound locally so electrum-ltc keeps building
              # until nixpkgs catches up. Source: trezor-firmware/python/pyproject.toml.
              pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "keyring" ];
            });
          }
          // extraPythonOverrides python-final python-prev
        )
      ];
    };
}
