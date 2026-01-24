# Learnings - Sora Watermark Cleaner Fix

## CUDA Support
- NixOS Python environments often fail to locate CUDA libraries (`libcuda.so`, `libcudart.so`, `cudnn`) even when `cudaSupport` is enabled globally.
- Solution: Explicitly add `pkgs.linuxPackages.nvidia_x11`, `pkgs.cudaPackages.cudatoolkit`, and `pkgs.cudaPackages.cudnn` to `LD_LIBRARY_PATH` in the package wrapper.

## PyTorch Deprecations
- `torch.cuda.amp.autocast()` is deprecated in newer PyTorch versions and causes failures.
- Solution: Replace with `@torch.amp.autocast('cuda')` using `substituteInPlace`.

## Build Environment
- Unfree packages (like NVIDIA drivers) require `NIXPKGS_ALLOW_UNFREE=1` and `--impure` when building with `nix build` if not configured in the flake directly for the build user.
- Using `path:.` as the flake reference ensures gitignored files (like `secrets.nix`) are included in the build context, preventing "file not found" errors during evaluation.
