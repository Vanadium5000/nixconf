{ lib, ... }:
rec {
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

  temporaryOverrideModule = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to apply this temporary package override.";
    };

    target = lib.mkOption {
      type = lib.types.enum [
        "stable"
        "unstable"
      ];
      default = "stable";
      description = "Package set where this override is applied.";
    };

    finalVersion = lib.mkOption {
      type = lib.types.str;
      description = "Package version produced by the temporary override.";
    };

    removeWhen = lib.mkOption {
      type = lib.types.raw;
      default = _final: _prev: false;
      description = "Predicate called as final: prev: bool; true means the override is obsolete.";
    };

    action = lib.mkOption {
      type = lib.types.enum [
        "warn"
        "fail"
      ];
      default = "fail";
      description = "Whether an obsolete enabled override should warn or fail evaluation.";
    };

    reason = lib.mkOption {
      type = lib.types.str;
      description = "Why this override exists and when it should be removed.";
    };

    package = lib.mkOption {
      type = lib.types.raw;
      description = "Override function called as final: prev: package.";
    };
  };

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

  evalTemporaryOverrides =
    target: overrides: final: prev:
    lib.mapAttrsToList (
      name: override:
      let
        isObsolete = override.removeWhen final prev;
        message = "temporary nixpkgs override `${target}.${name}` is obsolete: ${override.reason}";
      in
      if !override.enable || override.target != target || !isObsolete then
        null
      else if override.action == "fail" then
        throw message
      else
        message
    ) overrides;

  mkTemporaryOverridesOverlay =
    target: overrides: final: prev:
    builtins.foldl' (
      acc: name:
      let
        override = overrides.${name};
      in
      if !override.enable || override.target != target then
        acc
      else
        acc
        // {
          ${name} =
            let
              isObsolete = override.removeWhen final prev;
            in
            if isObsolete && override.action == "fail" then
              throw "temporary nixpkgs override `${target}.${name}` is obsolete: ${override.reason}"
            else
              let
                package = override.package final prev;
                actualVersion = package.version or null;
                checkedPackage =
                  if actualVersion != override.finalVersion then
                    throw "temporary nixpkgs override `${target}.${name}` produced version ${toString actualVersion}, expected ${override.finalVersion}"
                  else
                    package;
              in
              if isObsolete then
                builtins.trace "temporary nixpkgs override `${target}.${name}` is obsolete: ${override.reason}" checkedPackage
              else
                checkedPackage;
        }
    ) { } (builtins.attrNames overrides);

  mkNixpkgsConfig =
    {
      allowedUnfree ? [ ],
      allowUnfree ? commonConfig.allowUnfree,
    }:
    commonConfig
    // {
      inherit allowUnfree;
      allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowedUnfree;
    };

  mkSharedOverlays =
    {
      inputs,
      self,
      system ? null,
      unstableConfig ? null,
      extraPythonOverrides ? (_python-final: _python-prev: { }),
      temporaryOverrides ? { },
    }:
    [
      (mkSharedOverlay {
        inherit
          inputs
          self
          system
          unstableConfig
          extraPythonOverrides
          temporaryOverrides
          ;
      })
      (mkTemporaryOverridesOverlay "stable" temporaryOverrides)
      inputs.nix4vscode.overlays.default
    ];

  mkPkgs =
    {
      inputs,
      self,
      system,
      config ? commonConfig,
      extraPythonOverrides ? (_python-final: _python-prev: { }),
      temporaryOverrides ? { },
    }:
    import inputs.nixpkgs {
      inherit system config;
      overlays = mkSharedOverlays {
        inherit
          inputs
          self
          system
          extraPythonOverrides
          temporaryOverrides
          ;
      };
    };

  mkSharedOverlay =
    {
      inputs,
      self,
      system ? null,
      unstableConfig ? null,
      extraPythonOverrides ? (_python-final: _python-prev: { }),
      temporaryOverrides ? { },
    }:
    final: prev:
    let
      overlaySystem = if system == null then final.stdenv.hostPlatform.system else system;
    in
    {
      customPackages = self.packages.${overlaySystem};
      unstable = import inputs.nixpkgs-unstable (
        let
          config = if builtins.isFunction unstableConfig then unstableConfig final.config else unstableConfig;
        in
        {
          system = overlaySystem;
          overlays = [ (mkTemporaryOverridesOverlay "unstable" temporaryOverrides) ];
        }
        // lib.optionalAttrs (config != null) {
          # NixOS hosts pass final.config so pkgs.unstable observes the same nixpkgs
          # package policy as the system package set; flake-parts omits this to keep
          # its per-system package import behavior unchanged.
          inherit config;
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
