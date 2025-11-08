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

      cfg = config.preferences;
    in
    {
      options.preferences = {
        enable = mkOption {
          type = types.bool;
          default = true;
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
          ]
          // cfg.user.extraGroups;
          shell = self.packages.${pkgs.system}.environment;

          hashedPasswordFile = "/persist/passwd";
          initialPassword = "1234";
        };

        # Locales
        time.timeZone = cfg.timeZone;
        i18n.defaultLocale = cfg.locale;

        # SSH
        # Enable GnuPG with SSH support
        programs.gnupg.agent = {
          enable = true;
          enableSSHSupport = true;
          # Use curses-based PIN entry for terminal-only setups (avoids GUI prompts)
          pinentryFlavor = "curses";
        };

        # Disable the default SSH agent to avoid conflicts
        programs.ssh.startAgent = false;
      };
    };
}
