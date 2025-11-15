{ self, ... }:
{
  flake.nixosModules.terminal =
    {
      # pkgs,
      # lib,
      config,
      ...
    }:
    let
      # inherit (lib) getExe;
      # selfpkgs = self.packages."${pkgs.stdenv.hostPlatform.system}";
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

      programs.direnv.enable = true;
      programs.direnv.nix-direnv.enable = true;

      # Git-sync, a utility to sync folders via git
      services.git-sync.enable = true;

      # Password-store folder
      services.git-sync.repositories = {
        passwords = {
          uri = "git@github.com:Vanadium5000/passwords.git";
          path = "/home/${config.preferences.user.username}/.local/share/password-store";
          interval = 300;
        };
      };
    };
}
