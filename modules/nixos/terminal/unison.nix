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
      # Uses Tailscale FQDNs for consistent hostname resolution (critical for archive hashing)
      remoteDetails =
        if config.preferences.hostName == "legion5i" then
          {
            name = "macbook";
            fqdn = "macbook.tailb91a72.ts.net";
          }
        else if config.preferences.hostName == "macbook" then
          {
            name = "legion5i";
            fqdn = "legion5i.tailb91a72.ts.net";
          }
        else
          null;
    in
    {
      options.services.unison-sync = {
        enable = mkEnableOption "Unison background synchronization over Tailscale";
      };

      config = mkIf cfg.enable {
        environment.systemPackages = [
          pkgs.unison
          pkgs.inotify-tools
        ];

        # SSH Configuration for the sync target
        programs.ssh.extraConfig = lib.mkIf (remoteDetails != null) ''
          Host sync-target
            HostName ${remoteDetails.fqdn}
            User ${user}
            # Keep connection alive for long-running watch sessions
            ServerAliveInterval 60
            ServerAliveCountMax 3
        '';

        # Systemd User Service for continuous sync using file monitoring
        systemd.user.services.unison-sync = lib.mkIf (remoteDetails != null) {
          description = "Unison Background Synchronization between ${config.preferences.hostName} and ${remoteDetails.name}";
          wantedBy = [ "default.target" ];

          serviceConfig = {
            Type = "simple";
            # Wait for connectivity before starting (uses SSH as reliable check)
            ExecStartPre = "${pkgs.writeShellScript "unison-wait-for-peer" ''
              for i in $(seq 1 30); do
                if ${pkgs.openssh}/bin/ssh -q -o BatchMode=yes -o ConnectTimeout=5 sync-target exit; then
                  exit 0
                fi
                sleep 2
              done
              echo "Peer sync-target not reachable via SSH after 60s"
              exit 1
            ''}";
            ExecStart = "${pkgs.unison}/bin/unison -batch default";
            Restart = "always";
            RestartSec = "3min";
            Environment = [
              "HOME=/home/${user}"
              "PATH=${
                lib.makeBinPath [
                  pkgs.unison
                  pkgs.openssh
                  pkgs.inotify-tools
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

            # Version compatibility - embeds version in archive names to prevent collisions
            addversionno = true

            # Robustness & Automation
            auto = true
            batch = true
            repeat = watch
            confirmbigdel = true
            prefer = newer
            times = true

            # Connection resilience
            retry = 3
            sshargs = -o BatchMode=yes -o ConnectTimeout=10

            # Backup conflicting files before overwriting
            backup = Name *
            backuploc = central
            backupdir = .unison/backups
            maxbackups = 5
          '';
        };

        # Persist Unison state (archives/backups) across reboots
        impermanence.home.cache.directories = [ ".unison" ];
      };
    };
}
