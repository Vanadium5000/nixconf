{ self, ... }:
{
  flake.nixosModules.terminal =
    {
      pkgs,
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
        self.nixosModules.tailscale
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
          user = config.preferences.user.username;
        };
      };

      # Environment Variables
      environment.variables = {
        # PASSWORD_STORE_DIR for stuff like passmenu
        PASSWORD_STORE_DIR = "$HOME/.local/share/password-store";
        FLAKE = config.preferences.configDirectory; # Config Directory
      };

      # Add environment packages to system packages
      environment.systemPackages =
        self.legacyPackages.${pkgs.stdenv.hostPlatform.system}.environmentPackages;
    };
}
