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
  };
}
