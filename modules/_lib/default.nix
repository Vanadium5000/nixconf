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
    persistence = import ./persistence.nix { inherit lib; };
  };
}
