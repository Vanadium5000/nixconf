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

        # Opencode
        self.nixosModules.opencode

        self.nixosModules.dev
        self.nixosModules.nix
        self.nixosModules.tailscale
        self.nixosModules.virtualisation
        self.nixosModules.unison
      ];

      security.polkit.enable = true;

      security.wrappers.pkexec = {
        # Enable the setuid bit → this is the critical part that makes pkexec actually work
        # Without this you get the famous "pkexec must be setuid root" error
        setuid = true;

        # The owner must be root – this is required for setuid to have any meaning
        owner = "root";

        # Group is traditionally also root (very common convention for setuid wrappers)
        # Changing it rarely makes sense unless you have very special requirements
        group = "root";

        # Source path: where the real (non-wrapped) pkexec binary lives
        # ${pkgs.polkit} expands to the current polkit package in your nixpkgs version
        # This line basically says: "wrap this particular binary and give it the s-bit"
        source = "${pkgs.polkit}/bin/pkexec";
      };

      hardware.enableRedistributableFirmware = true;

      programs.direnv.enable = true;
      programs.direnv.nix-direnv.enable = true;

      # Git-sync, a utility to sync folders via git
      services.git-sync.enable = true;

      # Password-store folder
      services.git-sync.repositories = {
        passwords = {
          uri = "github.com:Vanadium5000/passwords.git";
          path = "/home/${config.preferences.user.username}/.local/share/password-store";
          interval = 300;
          user = config.preferences.user.username;
        };
      };

      # Enable Unison synchronization
      services.unison-sync.enable = true;

      # Wireshark - Powerful network protocol analyzer
      programs.wireshark = {
        enable = true;
        package = pkgs.wireshark-cli; # CLI only for terminal environments
        dumpcap = {
          enable = true; # ← gives cap_net_raw/cap_net_admin to dumpcap wrapper
        };
      };

      # Environment Variables
      environment.variables = {
        # PASSWORD_STORE_DIR for stuff like rofi-passmenu
        PASSWORD_STORE_DIR = "$HOME/.local/share/password-store";
        FLAKE = config.preferences.configDirectory; # Config Directory
      };

      # Add environment packages to system packages
      environment.systemPackages =
        self.legacyPackages.${pkgs.stdenv.hostPlatform.system}.environmentPackages;

      # Declare the HOST as an environment variable for use in scripts, etc.
      environment.variables.HOST = config.preferences.hostName;
    };
}
