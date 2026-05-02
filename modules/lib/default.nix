{ lib, ... }:
{
  # Centralized library exports for the flake.
  # Access via `self.lib.*` in modules.
  #
  # Example usage:
  #   { self, ... }:
  #   let
  #     persist = self.lib.persistence.mkPersistent { ... };
  #     hyprConf = self.lib.generators.toHyprconf { attrs = { ... }; };
  #   in { ... }

  flake.lib = {
    # Persistence helpers for managing files across reboots (impermanence setups)
    persistence = import ./_internal/persistence.nix { inherit lib; };

    # Generator functions for various config formats
    generators = import ./_internal/generators.nix { inherit lib; };

    # Nixpkgs overlay helpers keep duplicated package overrides in one place
    # while callers preserve their own NixOS or flake-parts evaluation policy.
    nixpkgs = import ./_internal/nixpkgs.nix { inherit lib; };
  };
}
