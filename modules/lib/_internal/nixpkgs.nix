{ lib, ... }:

let
  policy = import ./nixpkgs/policy.nix { inherit lib; };
in
rec {
  inherit (policy)
    allowedUnfree
    commonConfig
    temporaryOverrides
    unstablePackageOverrides
    ;

  temporaryOverrideModule = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to apply this temporary package override.";
    };

    target = lib.mkOption {
      type = lib.types.oneOf [
        (lib.types.enum [
          "stable"
          "unstable"
        ])
        lib.types.str
      ];
      default = "stable";
      description = "Package set or flake input where this override is applied.";
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
      description = "Override function called as final: prev: package. Flake input overlays may also pass source: final: prev: package.";
    };
  };

  callTemporaryOverridePackage =
    override: final: prev: source:
    if (builtins.functionArgs override.package) ? final then
      override.package { inherit final prev source; }
    else
      override.package final prev;

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
                package = callTemporaryOverridePackage override final prev null;
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

  mkTemporaryFlakeInputOverlay =
    target: source: overrides: final: prev:
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
                package = callTemporaryOverridePackage override final prev source;
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
      config = if builtins.isFunction unstableConfig then unstableConfig final.config else unstableConfig;
      inputTemporaryOverrides = lib.filterAttrs (
        _name: override: override.enable && override.target != "stable" && override.target != "unstable"
      ) temporaryOverrides;
      inputOverlays = lib.mapAttrsToList (
        target: source: mkTemporaryFlakeInputOverlay target source temporaryOverrides
      ) (lib.filterAttrs (name: _source: builtins.hasAttr name inputTemporaryOverrides) inputs);
    in
    {
      customPackages = self.packages.${overlaySystem};
      unstable = import inputs.nixpkgs-unstable (
        {
          system = overlaySystem;
          overlays = [ (mkTemporaryOverridesOverlay "unstable" temporaryOverrides) ] ++ inputOverlays;
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
          policy.pythonPackageOverrides python-final python-prev
          // extraPythonOverrides python-final python-prev
        )
      ];
    } // unstablePackageOverrides final prev;
}
