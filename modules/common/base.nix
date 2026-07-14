{ self, ... }:
{
  flake.nixosModules.common =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        types
        mkEnableOption
        mkOption
        ;

      inherit (self) secrets;

      cfg = config.preferences;
    in
    {
      imports = [
        self.nixosModules.opensnitch
        self.nixosModules.user-hyprland-config
        self.nixosModules.fresh
        self.nixosModules.git
      ];

      options.preferences = {
        enable = mkEnableOption "the shared nixconf preference layer" // {
          default = true;
        };

        configDirectory = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Repository checkout used by helper scripts.
            Leave null to follow the primary user's home directory automatically.
          '';
        };

        configFiles = {
          source = mkOption {
            type = types.enum (builtins.attrValues self.lib.configFiles.sourceNames);
            default = "checkout";
            description = ''
              Source for repo-owned config files consumed by programs.
              `checkout` keeps symlinks to preferences.paths.configDirectory for local editing;
              `store` copies the flake inputs from the Nix store for hosts without ~/nixconf.
            '';
          };
        };

        hostName = mkOption {
          type = types.str;
          description = "Host name exported to networking and shell tooling.";
        };

        allowedUnfree = mkOption {
          type = types.listOf (types.str);
          default = [ ];
          description = "Additional unfree packages this host intentionally allows.";
        };

        autostart = mkOption {
          type = types.listOf (types.either types.str types.package);
          default = [ ];
          description = "Commands or packages started by the desktop session.";
        };

        profiles = {
          terminal.enable = mkEnableOption "the shared terminal profile";
          desktop.enable = mkEnableOption "the shared desktop profile";
          laptop.enable = mkEnableOption "laptop-oriented defaults";
          server.enable = mkEnableOption "server-oriented defaults";
        };

        paths = {
          homeDirectory = mkOption {
            type = types.str;
            readOnly = true;
            description = "Primary user's home directory derived from preferences.user.username.";
          };

          configDirectory = mkOption {
            type = types.str;
            readOnly = true;
            description = "Final config checkout path after applying defaults.";
          };

          configSourceDirectory = mkOption {
            type = types.str;
            readOnly = true;
            description = "Effective repo-owned config source: checkout on editable hosts, Nix store on sealed hosts.";
          };

          sharedDirectory = mkOption {
            type = types.str;
            readOnly = true;
            description = "Shared top-level directory used by cross-host tooling and sync flows.";
          };

          vpnDirectory = mkOption {
            type = types.str;
            readOnly = true;
            description = "Directory containing VPN profiles consumed by proxy tooling.";
          };
        };

        user = {
          username = mkOption {
            type = types.str;
            description = "Primary interactive user managed by the host profile.";
          };
          extraGroups = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "Additional groups granted to the primary user.";
          };
        };

        hardware = {
          tlp = {
            enable = mkEnableOption "the laptop TLP tuning module";
            chargeControl = mkOption {
              type = types.enum [
                "none"
                "lenovo-conservation"
              ];
              default = "none";
              description = ''
                Battery charge-control backend for TLP. Lenovo non-ThinkPad
                systems expose only conservation mode, while unsupported
                hardware must not receive threshold settings that TLP rejects.
              '';
            };
          };
          memory.enable = mkEnableOption "zram and systemd-oomd memory-pressure tuning";
          btrfsMaintenance = {
            enable = mkEnableOption "low-risk Btrfs and SSD maintenance timers";
            dedupe = {
              enable = mkEnableOption "bees Btrfs deduplication for duplicate extents";
              hashTableSizeMB = mkOption {
                type = types.ints.positive;
                default = 1024;
                description = "Memory budget for the bees extent hash table, in MiB.";
              };
              loadAverageTarget = mkOption {
                type = types.str;
                default = "1.0";
                description = "bees --loadavg-target value used to throttle deduplication work.";
              };
            };
          };
        };

        system = {
          backlightDevice = mkOption {
            type = types.str;
            example = "intel_backlight";
          };

          keyboardBacklightDevice = mkOption {
            type = types.str;
            example = "platform::kbd_backlight";
          };
        };

        # Locales
        timeZone = mkOption {
          type = types.str;
          default = "Europe/London";
          description = "System time zone shared by host and user tooling.";
        };
        locale = mkOption {
          type = types.str;
          default = "en_GB.UTF-8";
          description = "Default system locale for shells and services.";
        };

        # Git identity
        git = {
          username = mkOption {
            type = types.str;
            description = "Git author/committer name";
          };
          email = mkOption {
            type = types.str;
            description = "Git author/committer email";
          };
        };
      };

      config = lib.mkIf cfg.enable (
        let
          homeDirectory = "/home/${cfg.user.username}";
          configDirectory =
            if cfg.configDirectory != null then cfg.configDirectory else "${homeDirectory}/nixconf";
          configFilesStore = self.lib.configFiles.mkStoreRoot { inherit pkgs; };
        in
        {
          preferences.paths = {
            inherit homeDirectory configDirectory;
            configSourceDirectory = self.lib.configFiles.mkSourceDirectory {
              source = cfg.configFiles.source;
              checkoutDirectory = configDirectory;
              storeDirectory = configFilesStore;
            };
            sharedDirectory = "${homeDirectory}/Shared";
            vpnDirectory = "${homeDirectory}/Shared/VPNs";
          };

          preferences.git = {
            # Keep the shared defaults non-identifying so host modules can stay
            # declarative without committing personal git identities.
            username = lib.mkDefault cfg.user.username;
            email = lib.mkDefault "${cfg.user.username}@${cfg.hostName}.local";
          };

          users.users.${cfg.user.username} = {
            isNormalUser = true;
            home = cfg.paths.homeDirectory;
            createHome = true;

            packages = self.legacyPackages.${pkgs.stdenv.hostPlatform.system}.environmentPackages;

            extraGroups = [
              "wheel"
              "networkmanager"
              "audio"
              "video"
              "libvirtd"
              "docker"
              "ydotool" # Wayland automation tool
              "pipewire"
              "dialout" # For serial port access (e.g. ESP32)
              "input"
            ]
            ++ cfg.user.extraGroups;
            shell = self.packages.${pkgs.stdenv.hostPlatform.system}.environment;
            uid = 1000; # Set explicitly

            hashedPassword = secrets.PASSWORD_HASH;
          };

          # Helpful for things like SystemD Emergency Mode
          users.users.root.hashedPassword = secrets.PASSWORD_HASH;

          # Add the default shell to environment
          environment.shells = [ self.packages.${pkgs.stdenv.hostPlatform.system}.environment ];

          # Persist generic CLI download/build caches in the cache tier so they
          # survive reboot without being backup-worthy home state.
          # Sources: modules/common/impermanence.nix cache split; upstream tldr cache path.
          impermanence.home.cache.directories = [
            ".cache/tealdeer"
          ];

          # Quickshell/DMS, Flatpak app discovery, IDEs, and systemd cgroup
          # tracking all allocate inotify watches in a busy graphical session;
          # the kernel reports ENOSPC here as "No space left on device" even
          # when disks are fine. Size this above the observed boot exhaustion.
          boot.kernel.sysctl = {
            "fs.inotify.max_user_watches" = 1048576;
            "fs.inotify.max_user_instances" = 1048576;
            "fs.inotify.max_queued_events" = 131072;
          };

          # Locales
          time.timeZone = cfg.timeZone;
          i18n.defaultLocale = cfg.locale;

          # SSH
          # Enable GnuPG with SSH support
          programs.gnupg.agent = {
            enable = true;
            enableSSHSupport = true;
            # Use Pinentry Qt on graphical hosts by default; server hosts can override.
            pinentryPackage = pkgs.pinentry-qt;
          };
          environment.systemPackages = [ pkgs.pinentry-qt ];

          # OpenSSH
          services.openssh = {
            enable = true;
            settings = {
              PermitRootLogin = "yes";
              PasswordAuthentication = false;
            };
          };

          # Disable the default SSH agent to avoid conflicts
          programs.ssh.startAgent = false;

          services.opensnitch.mutableRules = lib.mkIf config.services.opensnitch.enable {
            "030-allow-ssh-standard-ports" = {
              created = "2026-07-09T00:00:00Z";
              updated = "2026-07-09T00:00:00Z";
              name = "030-allow-ssh-standard-ports";
              description = "Allow the configured OpenSSH client package to ports 22 and 443 only; unusual ports still prompt for review.";
              action = "allow";
              duration = "always";
              enabled = true;
              precedence = false;
              nolog = false;
              operator = {
                type = "list";
                operand = "list";
                data = "";
                sensitive = false;
                list = [
                  {
                    type = "simple";
                    operand = "process.path";
                    data = "${pkgs.openssh}/bin/ssh";
                    sensitive = false;
                    list = null;
                  }
                  {
                    type = "regexp";
                    operand = "dest.port";
                    data = "^(22|443)$";
                    sensitive = false;
                    list = null;
                  }
                ];
              };
            };
          };

          # Bootloader
          # Use the grub EFI boot loader.
          # NOTE: No need to set devices, disko will add all devices that have a EF02 partition to the list already
          boot.loader = {
            grub.enable = true;
            grub.efiSupport = true;
            grub.efiInstallAsRemovable = true;
            grub.configurationLimit = 5;
          };

          # Alfa AWUS036AX (RTL8832BU/RTL8852BU chipset) WiFi adapter support
          # Using in-kernel rtw89_8852bu driver (requires kernel 6.14+)
          # Pros: Upstream (no DKMS breaks), standard mac80211 stack
          boot.kernelModules = [
            "rtw89_8852bu"

            "ch341" # Load CH340/CH341 USB-to-Serial driver
          ];
          boot.blacklistedKernelModules = [ "rtl8xxxu" ]; # Prevent generic driver conflict
        }
      );
    };
}
