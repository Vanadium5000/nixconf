{ self, ... }:
{
  flake.nixosModules.terminal =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      cfg = lib.attrByPath [ "preferences" "profiles" "terminal" ] { enable = false; } config;
      hostName = lib.attrByPath [ "preferences" "hostName" ] null config;

      hostPackageExclusions = {
        macbook = [
          "sora-watermark-cleaner"
          "omniroute"
          "cliproxyapi"
          "cpa-usage-keeper"
        ];
        main_vps = [
          "antigravity-manager"
          "aptos-fonts"
          "brave-origin" # GUI browser; terminal hosts install all flake packages.
          "iloader"
          "powerpoint-mcp"
          "niri-screen-time"
          "sideloader"
          "sora-watermark-cleaner"
          "waydroid-total-spoof"
          "limux"
        ];
        legion5i = [
          "omniroute"
          "cliproxyapi"
          "cpa-usage-keeper"
        ];
        # Example: Add more hosts as needed
        # server_host = [ "some-gui-package" ];
      };

      # Get exclusions for current host (empty list if not defined)
      excludedPackages = if hostName == null then [ ] else hostPackageExclusions.${hostName} or [ ];

      # Filter self.packages, removing any that match the exclusion list
      filteredFlakePackages = lib.filterAttrs (
        name: _pkg: !builtins.elem name excludedPackages
      ) self.packages.${pkgs.stdenv.hostPlatform.system};
    in
    {
      imports = [
        # Requirements
        self.nixosModules.common
        self.nixosModules.zsh

        # Opencode
        self.nixosModules.opencode
        self.nixosModules.omp

        self.nixosModules.dev
        self.nixosModules.nix
        self.nixosModules.memory
        self.nixosModules.btrfs-maintenance
        self.nixosModules.tailscale
        self.nixosModules.virtualisation
        self.nixosModules.unison

        # VPN Proxy Services (SOCKS5 + HTTP CONNECT)
        self.nixosModules.vpn-proxy-service

        # Server services (disabled by default, enable per-host)
        self.nixosModules.acp-chat
        self.nixosModules.cliproxyapi
        self.nixosModules.cpa-usage-keeper
        self.nixosModules.omniroute
        self.nixosModules.services-auth-gateway
      ];

      config = lib.mkIf cfg.enable {
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

        # OMP/OMOS keeps mutable DBs, logs, plugins, and YAML under ~/.omp;
        # enable the bootstrap with terminal hosts so impermanence preserves that tree.
        # Source: local state layout observed at ~/.omp/agent/{config.yml,models.yml}.
        programs.omp.enable = lib.mkDefault true;

        # Git-sync, a utility to sync folders via git
        services.git-sync.enable = true;

        services.acp-chat = {
          # User requested all-host LAN bind without opening the NixOS firewall;
          # ACP UI receives this through the service --host flag.
          enable = true;
          host = "0.0.0.0";
          openFirewall = false;
        };

        # Password-store folder
        services.git-sync.repositories = {
          passwords = {
            uri = "github.com:Vanadium5000/passwords.git";
            path = "${config.preferences.paths.homeDirectory}/.local/share/password-store";
            interval = 300;
            user = config.preferences.user.username;
          };
        };

        # Network monitoring tools
        # - snitch: TUI for inspecting network connections (netstat for humans)
        # - mitmproxy: managed by services.mitmproxy module (monitoring/mitmproxy.nix)
        # - termshark: TUI packet analyzer (in environment.nix, uses tshark)

        # Grant network capture capabilities for packet sniffing tools
        security.wrappers.dumpcap = {
          source = "${pkgs.wireshark-cli}/bin/dumpcap";
          capabilities = "cap_net_raw,cap_net_admin+eip";
          owner = "root";
          group = "wireshark";
        };

        # Keep wireshark group for capture permissions (used by termshark)
        users.groups.wireshark = { };

        # Environment Variables
        environment.variables = {
          # PASSWORD_STORE_DIR for stuff like qs-passmenu
          PASSWORD_STORE_DIR = "$HOME/.local/share/password-store";
          FLAKE = config.preferences.paths.configDirectory; # Config Directory
        };

        # Add environment packages to system packages
        environment.systemPackages =
          # Add all packages exported by the Flake
          lib.attrValues filteredFlakePackages
          ++ (with pkgs; [
            parted
            exfatprogs

            wtype
            monero-cli
            electrum
            electrum-ltc
            foundry # provides "cast"
          ]);

        # Declare the HOST as an environment variable for use in scripts, etc.
        environment.variables.HOST = config.preferences.hostName;
      };
    };
}
