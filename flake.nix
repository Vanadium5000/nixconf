{
  description = "NixOS configuration flake for system setup and modules";

  inputs = {
    # Main Nix package repository providing unstable channel packages
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

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

    # My Neovim config using NVF
    nvf-neovim = {
      url = "github:Vanadium5000/nvf-neovim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Define flake outputs using flake-parts and import-tree for modular configuration
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
