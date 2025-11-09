{
  description = "NixOS configuration flake for system setup and modules";

  inputs = {
    # Main Nix package repository providing unstable channel packages
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

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

    # Alternative to Home Manager for user environment management
    hjem = {
      url = "github:feel-co/hjem";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Install flatpaks declaratively
    # https://github.com/gmodena/nix-flatpak
    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=v0.6.0";

    # My Neovim config using NVF
    nvf-neovim = {
      url = "github:Vanadium5000/nvf-neovim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Source flakes for Dank Material stuff
    # dankMaterialShell: The main shell configuration and assets
    dankMaterialShell = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # dms-cli: Command-line interface for Dank Material Shell
    dms-cli = {
      url = "github:AvengeMedia/danklinux";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # dgop: System monitoring tool used by Dank Material Shell
    dgop = {
      url = "github:AvengeMedia/dgop";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    # Substituters
    # NOTE: ?priority={num} specificies the priority of the substituter
    # NOTE: All of this is duplicated both in flake.nix and common/nix.nix
    # Lower means more priority - cache.nixos.org defaults to 40 priority so it is unchanged
    extra-substituters = [
      "https://cache.nixos.org?priority=1"
      "https://hyprland.cachix.org?priority=2"
      "https://nix-community.cachix.org?priority=2"
      "https://cache.soopy.moe?priority=4" # Apple T2
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo=" # Apple T2
    ];
  };

  # Define flake outputs using flake-parts and import-tree for modular configuration
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
