{ lib, ... }:
{
  # Centralized library exports for the flake.
  # Access via `self.lib.*` in modules.
  #
  # Example usage:
  #   { self, ... }:
  #   let
  #     persist = self.lib.persistence.mkPersistent { ... };
  #   in { ... }

  flake.lib = {
    # Persistence helpers for managing files across reboots (impermanence setups)
    persistence = import ./persistence.nix { inherit lib; };

    # NixOS activation-script helper for managing files in the primary user's home.
    userFiles = import ./user-files.nix { inherit lib; };

    # Repo-owned config file helpers decide between live checkout paths and
    # immutable flake-store paths consistently across wrappers and activation.
    configFiles = import ./config-files.nix {
      inherit lib;
      root = ./..;
    };

    # Git config rendering shared by the user config and background git services.
    git = import ./git.nix { inherit lib; };

    # Nixpkgs overlay helpers keep duplicated package overrides in one place
    # while callers preserve their own NixOS or flake-parts evaluation policy.
    nixpkgs = import ./nixpkgs.nix { inherit lib; };

    # Directory-per-package helpers keep packages/ and external-packages/
    # export rules identical without hardcoding package-specific paths.
    packages = import ./packages.nix { inherit lib; };

    # User package-manager paths/env stay shared between shell wrappers,
    # session env, and impermanence so Bun/npm/pnpm do not drift per module.
    userPackages = import ./user-packages.nix { inherit lib; };
  };
}
