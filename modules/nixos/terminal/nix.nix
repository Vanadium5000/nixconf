{ inputs, self, ... }:
{
  flake.nixosModules.nix =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      imports = [
        inputs.nix-index-database.nixosModules.nix-index
      ];
      programs.nix-index-database.comma.enable = true;

      nix = {
        settings.experimental-features = [
          "nix-command"
          "flakes"
        ];
        package = pkgs.lix;

        # Opinionated: disable channels
        channel.enable = false;

        # Workaround for https://github.com/NixOS/nix/issues/9574
        nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

        # Keep CLI `flake:nixpkgs-unstable` aligned with this flake's locked input,
        # so ad-hoc `nix run/shell/build` usage cannot drift to user/global registry pins.
        registry.nixpkgs-unstable.flake = inputs.nixpkgs-unstable;

        settings = {
          builders-use-substitutes = true;
          trusted-users = [
            config.preferences.user.username
            "root"
            "@wheel"
          ];

          # Speed
          http-connections = 128; # default is only 25(!) – signifficant speedup
        };
      };
      programs.nix-ld.enable = true;
      nixpkgs.config = {
        # Disable if you don't want unfree packages
        allowUnfree = false;

        # CVE-2024-23342: ecdsa timing side-channel attack allowing private key recovery.
        # Required by electrum-ltc (litecoin-wallet). Low-value wallet, acceptable risk.
        permittedInsecurePackages = [
          "python3.13-ecdsa-0.19.1"
          "openclaw-2026.4.11"
        ];

        # Exceptions
        allowUnfreePredicate =
          pkg:
          builtins.elem (lib.getName pkg) (
            [
              "nvidia-x11"
              "nvidia-settings"
              "torch"
              "triton"

              # Nvidia CUDA
              "cuda_cudart"
              "cuda_cccl"
              "libnpp"
              "libcublas"
              "libcufft"
              "cuda_nvcc"
              "cuda-merged"
              "cuda_cuobjdump"
              "cuda_gdb"
              "cuda_nvdisasm"
              "cuda_nvprune"
              "cuda_cupti"
              "cuda_cuxxfilt"
              "cuda_nvml_dev"
              "cuda_nvrtc"
              "cuda_nvtx"
              "cuda_profiler_api"
              "cuda_sanitizer_api"
              "libcurand"
              "libcusolver"
              "libnvjitlink"
              "libcusparse"
              "cudnn"

              # Dictation CUDA deps
              "libcufile"
              "libcusparse_lt"

              # Antigravity Manager
              "antigravity-manager"

              # Firmware
              "intel-ocl"
              "broadcom-bt-firmware"
              "b43-firmware"
              "xow_dongle-firmware"
              "facetimehd-calibration"
              "facetimehd-firmware"
            ]
            ++ config.preferences.allowedUnfree
          );
      };

      # Add overlays
      nixpkgs.overlays = [
        (final: prev: {
          customPackages = self.packages.${final.stdenv.hostPlatform.system};
          unstable = import inputs.nixpkgs-unstable {
            system = final.stdenv.hostPlatform.system;
            config = final.config; # Inherit nixpkgs config
          };
          nur = import inputs.nur {
            nurpkgs = prev;
            pkgs = prev;
          };
          # waydroid-nftables = prev.waydroid-nftables.overrideAttrs (_old: {
          #   # HACK: Temporary multi-instance override from taksan's fork until upstream merges.
          #   # Undo by deleting this override once https://github.com/waydroid/waydroid/pull/1990 lands.
          #   # Clear inherited nixpkgs patches because this fork's source layout no longer matches
          #   # the 1.5.4 revert patch context, which otherwise breaks evaluation during patchPhase.
          #   src = prev.fetchFromGitHub {
          #     owner = "taksan";
          #     repo = "waydroid";
          #     rev = "bcd79d5fc522fdac514fae1a06efd5f1d4e0d545"; # feat/multi-instance @ 2025-07-29
          #     hash = "sha256-F0++vTKbzOU/Fp2IE9hDZVswNpOVduj4/Z32ALLDI/Q=";
          #   };
          #   patches = [ ];
          # });
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

      environment.systemPackages = with pkgs; [
        # Nix tooling
        nil
        nixd
        statix
        alejandra
        manix
        nix-inspect
      ];
    };
}
