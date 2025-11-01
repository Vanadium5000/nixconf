{
  flake.nixosModules.common =
    {
      lib,
      config,
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
        };

        networking.hostName = cfg.hostname;
      };
    };
}
