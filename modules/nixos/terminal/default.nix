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
      # Per-host package exclusions
      # Add package names (matching pname or derivation name) to exclude from self.packages
      hostPackageExclusions = {
        macbook = [
          "sora-watermark-cleaner"
        ];
        # Example: Add more hosts as needed
        # ionos_vps = [ "some-gui-package" ];
      };

      # Get exclusions for current host (empty list if not defined)
      excludedPackages = hostPackageExclusions.${config.preferences.hostName} or [ ];

      # Filter self.packages, removing any that match the exclusion list
      filteredFlakePackages = lib.filterAttrs (
        name: _pkg: !builtins.elem name excludedPackages
      ) self.packages.${pkgs.stdenv.hostPlatform.system};
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

        # VPN Proxy Services (SOCKS5 + HTTP CONNECT)
        self.nixosModules.vpn-proxy-service
      ];

      # VPN Proxy (SOCKS5 on :10800, HTTP CONNECT on :10801)
      services.vpn-proxy.enable = true;

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

      # Network monitoring tools
      # - snitch: TUI for inspecting network connections (netstat for humans)
      # - mitmproxy: HTTPS traffic inspection via proxy (apps must trust its CA)
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
        FLAKE = config.preferences.configDirectory; # Config Directory
      };

      # Add environment packages to system packages
      environment.systemPackages =
        # Add all packages exported by the Flake
        lib.attrValues filteredFlakePackages
        ++ (with pkgs; [
          mitmproxy # HTTPS interception proxy - run `mitmproxy` or `mitmweb`
          whisper-cpp
          wtype
          monero-cli
          electrum
          electrum-ltc
          foundry # provides "cast"
        ]);

      # Declare the HOST as an environment variable for use in scripts, etc.
      environment.variables.HOST = config.preferences.hostName;
    };
}
