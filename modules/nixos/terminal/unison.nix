{ ... }:
{
  flake.nixosModules.unison =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      inherit (lib) mkEnableOption mkIf;
      cfg = config.services.unison-sync;
      user = config.preferences.user.username;

      # Determine remote host based on current host for safe, targeted sync
      # Legion 5i (100.97.223.117) <-> MacBook (100.97.223.84)
      remoteDetails =
        if config.preferences.hostName == "legion5i" then
          {
            name = "macbook";
            ip = "100.115.218.120";
          }
        else if config.preferences.hostName == "macbook" then
          {
            name = "legion5i";
            ip = "100.97.223.117";
          }
        else
          null;
    in
    {
      options.services.unison-sync = {
        enable = mkEnableOption "Unison background synchronization over Tailscale";
      };

      config = mkIf cfg.enable {
        environment.systemPackages = [ pkgs.unison ];

        # SSH Configuration for the sync target
        programs.ssh.extraConfig = lib.mkIf (remoteDetails != null) ''
          Host sync-target
            HostName ${remoteDetails.ip}
            User ${user}
            # Identityfile unspecified/managed by GPG Agent
            # Keep connection alive for long-running watch sessions
            ServerAliveInterval 60
            ServerAliveCountMax 3
        '';

        # Systemd User Service for continuous sync using file monitoring
        # User services inherit the user's environment (including SSH_AUTH_SOCK from GPG agent)
        systemd.user.services.unison-sync = lib.mkIf (remoteDetails != null) {
          description = "Unison Background Synchronization between ${config.preferences.hostName} and ${remoteDetails.name}";
          # Note: User services usually don't wait for network-online.target as they start in user session.
          # We rely on Restart=always to handle initial connectivity issues.
          wantedBy = [ "default.target" ];

          serviceConfig = {
            Type = "simple";
            # -batch: run without user interaction
            # -repeat watch: use file monitoring to sync immediately on change
            ExecStart = "${pkgs.unison}/bin/unison -batch -repeat watch default";
            Restart = "always";
            RestartSec = "3min";
            Environment = [
              "HOME=/home/${user}"
              "PATH=${
                lib.makeBinPath [
                  pkgs.unison
                  pkgs.openssh
                ]
              }"
            ];
          };
          unitConfig = {
            StartLimitIntervalSec = 0;
          };
        };

        # Shared Unison Profile Configuration
        hjem.users."${user}" = {
          files.".unison/default.prf".text = ''
            # Roots: Local home directory vs Remote sync-target home (via SSH)
            root = /home/${user}
            root = ssh://${user}@sync-target//home/${user}

            # Selective Sync: Only sync the Shared folder
            path = Shared

            # Ignore patterns for efficiency and to avoid syncing garbage
            ignore = Name {.*,.*~}
            ignore = Name {node_modules,target,.git,.direnv}
            ignore = Name {.DS_Store,.localized,Icon\r}
            ignore = Name {.cache,.local/share/Trash,Downloads}

            # Robustness & Automation
            auto = true
            batch = true
            confirmbigdel = true
            prefer = newer
            times = true
          '';
        };

        # Persist Unison state (archives/backups) across reboots
        impermanence.home.directories = [ ".unison" ];
      };
    };
}
