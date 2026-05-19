_:

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

  temporaryOverrides = { };

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
