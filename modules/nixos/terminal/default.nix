{ self, ... }:
{
  flake.nixosModules.terminal =
    {
      # pkgs,
      # lib,
      ...
    }:
    let
      # inherit (lib) getExe;
      # selfpkgs = self.packages."${pkgs.system}";
    in
    {
      imports = [
        self.nixosModules.nix
      ];
    };
}
