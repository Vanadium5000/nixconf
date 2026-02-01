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
          "deep-live-cam"
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

      # =========================================================================
      # Out-Of-Memory Daemon (systemd-oomd) Configuration
      # =========================================================================
      # Prevents system freezes by proactively killing memory-hungry processes
      # before the kernel's OOM killer kicks in (which is more disruptive).
      #
      # Kill priority (first to last):
      #   1. Build processes (nix-daemon) - restartable, often spawns 100+ compilers
      #   2. Background services - less critical
      #   3. User session (desktop) - protected, killing is very disruptive

      systemd.oomd = {
        enable = true;
        enableRootSlice = true; # Monitor root slice for comprehensive coverage
        enableSystemSlice = true; # System services including nix-daemon
        enableUserSlices = true; # User sessions and applications
        extraConfig = {
          SwapUsedLimit = "90%"; # Start killing at 90% swap usage
          DefaultMemoryPressureDurationSec = "20s"; # 20s sustained pressure before kill
        };
      };

      # Configure nix-daemon as primary kill target under memory pressure
      # During builds, nix spawns many child processes (compilers, linkers, etc.)
      # that consume large amounts of RAM. Killing builds is safe - they restart.
      systemd.services.nix-daemon.serviceConfig = {
        ManagedOOMMemoryPressure = "kill"; # Enable pressure-based killing
        ManagedOOMMemoryPressureLimit = "50%"; # Kill early to prevent cascade
      };

      # Protect user graphical session from being killed
      # Desktop compositor and apps should survive memory pressure events
      systemd.slices.user.sliceConfig = {
        ManagedOOMPreference = "avoid"; # oomd will try to avoid killing this slice
      };

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
