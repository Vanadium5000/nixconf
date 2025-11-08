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
        # Requirements
        self.nixosModules.common

        self.nixosModules.dev
        self.nixosModules.nix
      ];

      security.polkit.enable = true;
      hardware.enableRedistributableFirmware = true;
    };
}
