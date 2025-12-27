{ inputs, ... }:
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

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      nix.package = pkgs.lix;
      nix.settings = {
        # Substituters
        # NOTE: ?priority={num} specificies the priority of the substituter
        # NOTE: All of this is duplicated both in flake.nix and common/nix.nix
        # Lower means more priority - cache.nixos.org defaults to 40 priority so it is unchanged
        extra-substituters = [
          "https://cache.nixos.org?priority=1"
          "https://hyprland.cachix.org?priority=2"
          "https://nix-community.cachix.org?priority=2"
          "https://cache.nixos-cuda.org?priority=3" # Cuda
          "https://cache.soopy.moe?priority=4" # Apple T2
        ];
        extra-trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" # Cuda
          "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo=" # Apple T2
        ];
        builders-use-substitutes = true;
        trusted-users = [
          config.preferences.user.username
          "root"
          "@wheel"
        ];
      };
      programs.nix-ld.enable = true;
      nixpkgs.config = {
        # Disable if you don't want unfree packages
        allowUnfree = false;

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
            ]
            ++ config.preferences.allowedUnfree
          );
      };

      # Add overlays
      nixpkgs.overlays = [
        (final: prev: {
          unstable = import inputs.nixpkgs-unstable {
            system = final.system;
          };
          nur = import inputs.nur {
            nurpkgs = prev;
            pkgs = prev;
          };
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
