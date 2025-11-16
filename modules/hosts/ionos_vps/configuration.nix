{ self, inputs, ... }:
{
  flake.nixosConfigurations.ionos_vps = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      self.nixosModules.ionos_vpsHost
    ];
  };

  flake.nixosModules.ionos_vpsHost =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        self.nixosModules.terminal

        # Disko
        inputs.disko.nixosModules.disko
        self.diskoConfigurations.ionos_vps
      ];

      # Enable SSH support
      users.users.${config.preferences.user.username}.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFsIUmSPfK9/ncfGjINjeI7sz+QK7wyaYJZtLhVpiU66 thealfiecrawford@icloud.com"
      ];

      # Use terminal-friendly curses backend
      programs.gnupg.agent.pinentryPackage = lib.mkForce pkgs.pinentry-curses;

      # Disable git-sync for passwords, I don't want any important credentials on the system
      services.git-sync.enable = lib.mkForce false;

      # Preferences
      preferences = {
        user = {
          username = "main";
        };
      };

      # No cuda - doesn't have an Nvidia GPU
      nixpkgs.config.cudaSupport = false;

      # State version
      system.stateVersion = "25.11";
    };
}
