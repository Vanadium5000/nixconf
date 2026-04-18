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
      imports = [ self.nixosModules.extra_hjem ];

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

        hardware.tlp.enable = mkEnableOption "the laptop TLP tuning module";

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
        in
        {
          preferences.paths = {
            inherit homeDirectory configDirectory;
            sharedDirectory = "${homeDirectory}/Shared";
            vpnDirectory = "${homeDirectory}/Shared/VPNs";
          };

          users.users.${cfg.user.username} = {
            isNormalUser = true;

            packages = self.legacyPackages.${pkgs.stdenv.hostPlatform.system}.environmentPackages;

            extraGroups = [
              "wheel"
              "networkmanager"
              "audio"
              "video"
              "libvirtd"
              "podman"
              "ollama"
              "ydotool" # Wayland automation tool
              "pipewire"
              "wireshark" # Network capture permissions (for termshark/dumpcap)
              "dialout" # For serial port access (e.g. ESP32)
            ]
            ++ cfg.user.extraGroups;
            shell = self.packages.${pkgs.stdenv.hostPlatform.system}.environment;
            uid = 1000; # Set explicitly

            hashedPassword = secrets.PASSWORD_HASH;
          };

          # Add the default shell to environment
          environment.shells = [ self.packages.${pkgs.stdenv.hostPlatform.system}.environment ];

          # Pesist Tealdeer (a TLDR alternative) cache data
          impermanence.home.cache.directories = [
            ".cache/tealdeer"
          ];

          # Persist ZSH history
          impermanence.home.cache.files = [
            ".zsh_history"
          ];

          # Locales
          time.timeZone = cfg.timeZone;
          i18n.defaultLocale = cfg.locale;

          # Git global config
          hjem.users.${cfg.user.username}.files.".gitconfig".text = ''
            [user]
              name = ${cfg.git.username}
              email = ${cfg.git.email}
          '';

          # SSH
          # Enable GnuPG with SSH support
          programs.gnupg.agent = {
            enable = true;
            enableSSHSupport = true;
            # Use Pinentry Qt on graphical hosts by default; server hosts can override.
            pinentryPackage = pkgs.pinentry-qt;
          };

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

          # Bootloader
          # Use the grub EFI boot loader.
          # NOTE: No need to set devices, disko will add all devices that have a EF02 partition to the list already
          boot.loader = {
            grub.enable = true;
            grub.efiSupport = true;
            grub.efiInstallAsRemovable = true;
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
