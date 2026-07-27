{
  # External packages that should be evaluated against nixpkgs-unstable when
  # update-pkgs generates its temporary packages.nix for nix-update.
  edgePackages = [
    "cliproxyapi"
    "omniroute"
    "openchamber-web"
  ];

  # Curated update/test groups for external packages only. Local custom packages
  # live under packages/ and are intentionally not included in automatic coverage.
  packageSets = {
    light = [
      "omniroute"
      "openchamber-web"
      "cpa-usage-keeper"
    ];
    medium = [
      "cliproxyapi"
      "waydroid-script"
      "waydroid-total-spoof"
    ];
    heavy = [
      "wallpapers"
    ];
  };

  updateModes = {
    cpa-usage-keeper = "custom";
    cliproxyapi = "nix-update";
    omniroute = "custom";
    openchamber-web = "custom";
    update-pkgs = "manual";
    wallpapers = "manual";
    waydroid-script = "nix-update-branch";
    waydroid-total-spoof = "nix-update-branch";
  };

  smokeArguments = {
    cliproxyapi = "--help";
    cpa-usage-keeper = "--help";
    omniroute = "--help";
    openchamber-web = "--help";
    waydroid-script = "--help";
    waydroid-total-spoof = "--help";
  };

  # Custom updaters are keyed by package name so package.nix remains the
  # single source for sources/hashes while this workflow owns update strategy.
  customUpdaters = {
    cpa-usage-keeper = "cpa_usage_keeper";
    omniroute = "omniroute";
    openchamber-web = "openchamber_web";
  };

  manualReasons = {
    update-pkgs = "repo-local update workflow package";
    wallpapers = "pinned image set with many fixed URLs";
  };
}
