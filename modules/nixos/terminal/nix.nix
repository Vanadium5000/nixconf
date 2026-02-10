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
        ];

        # Exceptions
        allowUnfreePredicate =
          pkg:
          builtins.elem (lib.getName pkg) (
            [
              "nvidia-x11"
              "nvidia-settings"

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
          customPackages = self.packages.${final.system};
          unstable = import inputs.nixpkgs-unstable {
            system = final.system;
            config = final.config; # Inherit nixpkgs config
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
