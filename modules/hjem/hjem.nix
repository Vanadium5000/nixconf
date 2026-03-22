{ inputs, ... }:
{
  flake.nixosModules.extra_hjem =
    { config, ... }:
      let
        user = config.preferences.user.username;
      in
      {
      imports = [
        inputs.hjem.nixosModules.default
      ];

      config = {
        hjem = {
          users."${user}" = {
            enable = true;
            directory = config.preferences.paths.homeDirectory;
            user = "${user}";
          };

          # overwrite existing unmanaged files, if present
          clobberByDefault = true;
        };
      };
    };
}
