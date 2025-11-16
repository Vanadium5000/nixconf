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
      nix.settings.trusted-users = [ config.preferences.user.username ];
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
