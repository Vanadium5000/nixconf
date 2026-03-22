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

      # Server services — only enabled on this VPS host
      services.openclaw.enable = true;

      services.opencode-server = {
        enable = true;
        hostname = "127.0.0.1"; # Secure: bind localhost only, nginx proxies publicly
      };

      services.cliproxyapi = {
        enable = true;
        host = "127.0.0.1"; # Secure: bind localhost only
        openFirewall = false; # Secure: close public port
      };

      services.vpn-proxy = {
        enable = true;
        bindAddress = "127.0.0.1"; # Secure: bind localhost only
      };
      services.unison-sync.enable = true;

      # System monitoring — real-time metrics with persistent history
      services.netdata-monitor.enable = true;

      # Fleet dashboard portal — accessible via Tailscale at http://ionos-vps:8082
      services.homepage-monitor.enable = true;

      # HTTPS traffic analyzer — on-demand: systemctl start mitmproxy
      services.mitmproxy.enable = true;
      services.mitmproxy.trustCA = true;

      # Preferences
      preferences = {
        hostName = "ionos_vps";
        profiles = {
          terminal.enable = true;
          server.enable = true;
        };
        user = {
          username = "main";
        };
        git = {
          username = "Vanadium5000";
          email = "vanadium5000@gmail.com";
        };
      };

      # No cuda - doesn't have an Nvidia GPU
      nixpkgs.config.cudaSupport = false;

      # State version
      system.stateVersion = "25.11";
    };
}
