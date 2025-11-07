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
        hostname = mkOption {
          type = types.str;
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

        networking.hostName = cfg.hostname;

        # Locales
        time.timeZone = cfg.timeZone;
        i18n.defaultLocale = cfg.locale;
      };
    };
}
