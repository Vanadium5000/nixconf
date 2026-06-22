{ inputs, ... }:
{
  flake.nixosModules.bifrost =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      upstreamPackages = inputs.bifrost.packages.${system};
      bifrostUi = upstreamPackages.bifrost-ui.overrideAttrs (oldAttrs: {
        # Upstream tag transports/v1.5.15 ships stale fixed-output hashes while
        # keeping its flake/package API correct. Patch only the hashes here and
        # keep using upstream's derivations/module. Source: local nix build FOD
        # mismatch for bifrost-ui-1.4.9-npm-deps.
        npmDeps = oldAttrs.npmDeps.overrideAttrs (_: {
          outputHash = "sha256-moj6gveRUIbqkv1YagSPi8HECq34TY6UqwSk2obr8C0=";
        });
      });
      bifrostHttp =
        (upstreamPackages.bifrost-http.override { bifrost-ui = bifrostUi; }).overrideAttrs
          (_: {
            # Same upstream tag also has a stale Go vendor fixed-output hash.
            vendorHash = "sha256-B5Df/1iOCL6VSSxRub49aCAQEnPJ+5lD4rJE6Loepg0=";
          });
    in
    {
      imports = [ inputs.bifrost.nixosModules.bifrost ];
      config = lib.mkIf config.services.bifrost.enable {
        services.bifrost.package = lib.mkOverride 900 bifrostHttp;

        users.groups.bifrost = { };
        users.users.bifrost = {
          isSystemUser = true;
          group = "bifrost";
          home = toString config.services.bifrost.stateDir;
          description = "Bifrost AI gateway service user";
        };

        systemd.services.bifrost.serviceConfig = {
          # Upstream defaults to DynamicUser, but main_vps already had a public
          # /var/lib/bifrost persistence mount. systemd rejects that combination
          # before ExecStartPre with status=238/STATE_DIRECTORY, so use a stable
          # service user for this repo module.
          DynamicUser = lib.mkForce false;
          User = "bifrost";
          Group = "bifrost";
          StateDirectoryMode = "0700";
        };
      };
    };
}
