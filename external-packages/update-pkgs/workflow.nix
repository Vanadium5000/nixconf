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

  manualReasons = {
    update-pkgs = "repo-local update workflow package";
    wallpapers = "pinned image set with many fixed URLs";
  };
}
