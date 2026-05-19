{
  description = "NixOS configuration flake for system setup and modules";

  inputs = {
    # Main Nix package repository providing stable channel packages
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # Fallback Nix package repository providing unstable channel packages
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # NUR - extra user-created packages for NixOS
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hardware configs/drivers
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Utility for wrapping applications and executables
    wrappers.url = "github:Lassulus/wrappers/39b27c1bbf6cfc38afb570f98664540639fc52f8";

    # Framework for modular Nix flake structure and composition
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Tool for importing directory trees as Nix modules
    import-tree.url = "github:vic/import-tree";

    # Database for nix-index, enabling fast package searching
    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Module for managing impermanent (ephemeral) file systems
    impermanence.url = "github:nix-community/impermanence";

    # Tool for retroactive persistence in NixOS configurations
    persist-retro.url = "github:Geometer1729/persist-retro";

    # Declarative disk partitioning and formatting tool
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Install flatpaks declaratively
    # https://github.com/gmodena/nix-flatpak
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.7.0";

    # Automatically updated extensions - no more being months or years & missing extensions for VSCodium
    nix4vscode = {
      # nix4vscode is broken for latest versions
      url = "github:nix-community/nix4vscode";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # HyprQt6Engine
    # TODO: Switch to hyprqt6engine when it is added to nixpkgs
    hyprqt6engine = {
      url = "github:hyprwm/hyprqt6engine";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # DankMaterialShell upstream NixOS module and package.
    # Source: https://danklinux.com/docs/dankmaterialshell/nixos
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # OpenCode upstream flake; use this instead of the nixpkgs unstable package
    # so the installed CLI tracks anomalyco/opencode's own build output.
    opencode = {
      url = "github:anomalyco/opencode";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # Dokploy NixOS module for self-hosted deployment orchestration.
    # Follow the main nixpkgs input so option defaults stay in the same package universe.
    nix-dokploy = {
      url = "github:el-kurto/nix-dokploy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    # Substituters
    # Lower priority wins; keep partial caches after cache.nixos.org (40) so they only rescue misses.
    # Keep rebuilding from source when a third-party cache is flaky instead of
    # turning a transient DNS outage into a hard failure.
    fallback = true;
    # DNS/CDN resolution can exceed 5s on flaky links; 15s avoids false cache misses without hanging indefinitely.
    # Source: https://nixos.org/manual/nix/stable/command-ref/conf-file#conf-connect-timeout
    connect-timeout = 15;
    stalled-download-timeout = 300;
    # Rebuild-time fan-out for slow CDN paths; persisted in modules/nixos/terminal/nix.nix.
    # Source: https://nixos.org/manual/nix/stable/command-ref/conf-file#conf-http-connections
    http-connections = 256;
    max-substitution-jobs = 96;
    extra-substituters = [
      # Project/CDN caches are incomplete; query them only after official misses.
      # Sources: https://cachix.org/ https://cache.numtide.com/ https://cache.nixos.org/nix-cache-info
      "https://cache.numtide.com?priority=20"
      "https://cache.nixos.org?priority=40"
      "https://cache.nixos-cuda.org?priority=45"
      "https://nix-community.cachix.org?priority=50"
      "https://hyprland.cachix.org?priority=51" # Hyprland
      "https://cache.soopy.moe?priority=53" # Apple T2
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=" # Hyprland
      "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo=" # Apple T2
    ];
  };

  # Define flake outputs using flake-parts and import-tree for modular configuration.
  # `path:.#...` consumers rely on this import-tree set staying complete even when the
  # working tree is dirty or includes generated files like `secrets.nix`.
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake
      {
        inherit inputs;
      }
      (
        inputs.import-tree [
          ./modules
          ./secrets.nix
        ]
      );
}
