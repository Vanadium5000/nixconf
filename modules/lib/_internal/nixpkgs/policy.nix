{ lib }:

let
  bun_1_3_14_sources = pkgs: {
    "aarch64-darwin" = pkgs.fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.14/bun-darwin-aarch64.zip";
      hash = "sha256-2LliIYKK1vl6x6wKt+lYcjQa92MAHogD6CZ2UsJlJiA=";
    };
    "aarch64-linux" = pkgs.fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.14/bun-linux-aarch64.zip";
      hash = "sha256-on/7Y6gxA3WDbg1vZorhf6jY0YuIw3yCHGUzGXOhmjs=";
    };
    "x86_64-darwin" = pkgs.fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.14/bun-darwin-x64-baseline.zip";
      hash = "sha256-PjWtb1OXGpg0v55nhuKt9ytfGSHMmpxf3gc9KXKUQHY=";
    };
    "x86_64-linux" = pkgs.fetchurl {
      url = "https://github.com/oven-sh/bun/releases/download/bun-v1.3.14/bun-linux-x64.zip";
      hash = "sha256-lR7iruhV8IWVruxiJSJqKY0/6oOj3NZGXAnLzN9+hI8=";
    };
  };
in
{
  commonConfig = {
    # Flake/package evaluation must be permissive enough to expose all package
    # outputs; NixOS policy narrows unfree packages with allowUnfreePredicate.
    allowUnfree = true;

    # CVE-2024-23342: ecdsa timing side-channel attack allowing private key recovery.
    # Required by electrum-ltc (litecoin-wallet). Low-value wallet, acceptable risk.
    permittedInsecurePackages = [
      "python3.13-ecdsa-0.19.1"
    ];
  };

  allowedUnfree = [
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
  ];

  temporaryOverrides = {
    bun = {
      enable = true;
      target = "unstable";
      finalVersion = "1.3.14";
      removeWhen = _final: prev: lib.versionAtLeast prev.bun.version "1.3.14";
      action = "fail";
      reason = "nixpkgs-unstable bun is at least 1.3.14; remove the local 1.3.14 binary override.";
      package =
        _final: prev:
        let
          system = prev.stdenvNoCC.hostPlatform.system;
          sources = bun_1_3_14_sources prev;
        in
        prev.bun.overrideAttrs (old: {
          version = "1.3.14";
          src = sources.${system} or (throw "Unsupported bun system: ${system}");
          passthru = (old.passthru or { }) // {
            inherit sources;
          };
        });
    };
  };

  pythonPackageOverrides = python-final: python-prev: {
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
  };
}
