{ inputs, ... }:
{
  flake.nixosModules.nix =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      imports = [
        inputs.nix-index-database.nixosModules.nix-index
      ];
      programs.nix-index-database.comma.enable = true;

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      nix.package = pkgs.lix;
      programs.nix-ld.enable = true;
      nixpkgs.config = {
        # Disable if you don't want unfree packages
        allowUnfree = false;

        # Exceptions
        allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) config.preferences.allowedUnfree;
      };

      environment.systemPackages = with pkgs; [
        # Nix tooling
        nil
        nixd
        statix
        alejandra
        manix
        nix-inspect
      ];
    };
}
