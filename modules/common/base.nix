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
        mkOption
        ;

      inherit (self) secrets;

      cfg = config.preferences;
    in
    {
      options.preferences = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };

        configDirectory = mkOption {
          type = types.str;
          default = "/home/${cfg.user.username}/nixconf";
        };

        hostName = mkOption {
          type = types.str;
        };

        allowedUnfree = mkOption {
          type = types.listOf (types.str);
          default = [ ];
        };

        autostart = mkOption {
          type = types.listOf (types.either types.str types.package);
          default = [ ];
        };

        user = {
          username = mkOption {
            type = types.str;
          };
          extraGroups = mkOption {
            type = types.listOf types.str;
            default = [ ];
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
        };
        locale = mkOption {
          type = types.str;
          default = "en_GB.UTF-8";
        };
      };

      config = lib.mkIf cfg.enable {
        users.users.${cfg.user.username} = {
          isNormalUser = true;

          extraGroups = [
            "wheel"
            "networkmanager"
            "audio"
            "video"
            "libvirtd"
            "podman"
            "ollama"
            "ydotool" # Wayland automation tool
          ]
          ++ cfg.user.extraGroups;
          shell = self.packages.${pkgs.stdenv.hostPlatform.system}.environment;

          hashedPassword = secrets.PASSWORD_HASH;
        };

        # Add the default shell to environment
        environment.shells = [ self.packages.${pkgs.stdenv.hostPlatform.system}.environment ];

        # Locales
        time.timeZone = cfg.timeZone;
        i18n.defaultLocale = cfg.locale;

        # SSH
        # Enable GnuPG with SSH support
        programs.gnupg.agent = {
          enable = true;
          enableSSHSupport = true;
          # Use Pinentry Qt
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
      };
    };
}
