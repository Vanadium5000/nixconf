{ lib }:

let
  mkPolicyEntry =
    {
      name,
      reason,
      owner,
      removeAfter ? null,
      source ? null,
    }:
    {
      inherit
        name
        reason
        owner
        removeAfter
        source
        ;
    };

  baseUnfreePolicy = [
    (mkPolicyEntry {
      name = "nvidia-kernel-modules";
      owner = "hosts/legion5i/configuration.nix";
      reason = "NVIDIA driver stack for legion5i graphics acceleration.";
    })
    (mkPolicyEntry {
      name = "nvidia-x11";
      owner = "hosts/legion5i/configuration.nix";
      reason = "NVIDIA userspace driver stack for legion5i graphics acceleration.";
    })
    (mkPolicyEntry {
      name = "nvidia-settings";
      owner = "hosts/legion5i/configuration.nix";
      reason = "NVIDIA control utility installed with the desktop GPU stack.";
    })
    (mkPolicyEntry {
      name = "torch";
      owner = "programmes/environment/module.nix";
      reason = "CUDA-enabled ML runtime used by local AI tooling.";
    })
    (mkPolicyEntry {
      name = "triton";
      owner = "programmes/environment/module.nix";
      reason = "Torch CUDA compiler/runtime dependency.";
    })
  ]
  ++
    map
      (
        name:
        mkPolicyEntry {
          inherit name;
          owner = "nixpkgs CUDA package set";
          reason = "CUDA support package required by GPU-enabled local tooling.";
        }
      )
      [
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
        "libcufile"
        "libcusparse_lt"
      ]
  ++
    map
      (
        name:
        mkPolicyEntry {
          inherit name;
          owner = "hosts/macbook";
          reason = "Firmware package required for host hardware support.";
        }
      )
      [
        "intel-ocl"
        "broadcom-bt-firmware"
        "b43-firmware"
        "xow_dongle-firmware"
        "facetimehd-calibration"
        "facetimehd-firmware"
      ];

  optInUnfreePolicy = [
    (mkPolicyEntry {
      name = "obsidian";
      owner = "modules/desktop/obsidian.nix";
      reason = "Native Obsidian desktop client enabled only by the Obsidian feature module.";
      source = "nixpkgs pkgs/by-name/ob/obsidian/package.nix";
    })
    (mkPolicyEntry {
      name = "vscode-extension-fill-labs-dependi";
      owner = "modules/desktop/vscodium/default.nix";
      reason = "VSCodium extension from Fill Labs enabled only by the VSCodium feature module.";
    })
    (mkPolicyEntry {
      name = "antigravity";
      owner = "modules/desktop/vscodium/default.nix";
      reason = "Google Antigravity editor enabled only by the VSCodium feature module.";
    })
    (mkPolicyEntry {
      name = "antigravity-with-extensions";
      owner = "modules/desktop/vscodium/default.nix";
      reason = "Google Antigravity wrapper with extensions enabled only by the VSCodium feature module.";
    })
    (mkPolicyEntry {
      name = "mongodb-ce";
      owner = "modules/terminal/dev.nix";
      reason = "MongoDB Community Edition service package enabled only by the dev module.";
    })
    (mkPolicyEntry {
      name = "mongodb-compass";
      owner = "modules/terminal/dev.nix";
      reason = "MongoDB Compass GUI enabled only by the dev module.";
    })
  ];

  unfreePolicy = baseUnfreePolicy ++ optInUnfreePolicy;

  insecurePolicy = [
    (mkPolicyEntry {
      name = "python3.13-ecdsa-0.19.2";
      owner = "modules/terminal/default.nix";
      reason = "CVE-2024-23342 affects electrum-ltc only; low-value wallet usage accepted until nixpkgs updates.";
      source = "https://nvd.nist.gov/vuln/detail/CVE-2024-23342";
    })
  ];

  names = entries: map (entry: entry.name) entries;
  uniqueNames = entries: lib.unique (names entries);
  namesForOwner = owner: entries: uniqueNames (builtins.filter (entry: entry.owner == owner) entries);
in
{
  commonConfig = {
    # Flake/package evaluation must be permissive enough to expose all package
    # outputs; NixOS policy narrows unfree packages with allowUnfreePredicate.
    allowUnfree = true;

    permittedInsecurePackages = uniqueNames insecurePolicy;
  };

  inherit unfreePolicy insecurePolicy;

  allowedUnfree = uniqueNames baseUnfreePolicy;
  allowedUnfreeFor = owner: namesForOwner owner unfreePolicy;
  permittedInsecure = uniqueNames insecurePolicy;

  temporaryOverrides = { };

  unstablePackageOverrides = final: _prev: {
    # Quickshell is a fast-moving shell runtime; route stable pkgs.quickshell
    # through nixpkgs-unstable so every caller uses the same current package.
    quickshell =
      let
        quickshell = final.unstable.quickshell;
      in
      final.symlinkJoin {
        name = "${quickshell.pname or "quickshell"}-${quickshell.version or "unstable"}-sanitized";
        paths = [ quickshell ];
        nativeBuildInputs = [ final.makeWrapper ];
        postBuild = ''
          for bin in quickshell qs; do
            if [ -x ${quickshell}/bin/$bin ]; then
              rm -f $out/bin/$bin
              makeWrapper ${quickshell}/bin/$bin $out/bin/$bin \
                --unset __QUICKSHELL_CRASH_INFO_FD \
                --unset __QUICKSHELL_CRASH_DUMP_PID
            fi
          done
        '';
        meta = quickshell.meta;
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
