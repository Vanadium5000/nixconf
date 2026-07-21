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

      # npm package-lock "os"/"cpu" tags (Node process.platform / process.arch).
      npmOs =
        if pkgs.stdenv.hostPlatform.isLinux then
          "linux"
        else if pkgs.stdenv.hostPlatform.isDarwin then
          "darwin"
        else
          throw "bifrost-ui: unsupported host OS for optional npm prune";
      npmCpu =
        if pkgs.stdenv.hostPlatform.isx86_64 then
          "x64"
        else if pkgs.stdenv.hostPlatform.isAarch64 then
          "arm64"
        else
          throw "bifrost-ui: unsupported host CPU for optional npm prune";

      # External script keeps Python out of the Nix string so nixfmt cannot reindent
      # a heredoc into an IndentationError (see omniroute postPatch caveat).
      pruneNonHostOptionalDeps = ''
        chmod u+w package-lock.json
        npmOs=${lib.escapeShellArg npmOs} npmCpu=${lib.escapeShellArg npmCpu} \
          ${lib.getExe pkgs.python3} ${./bifrost-prune-npm-optionals.py}
      '';

      bifrostUi = upstreamPackages.bifrost-ui.overrideAttrs (oldAttrs: {
        # Upstream tag transports/v1.5.15 ships stale fixed-output hashes while
        # keeping its flake/package API correct. Patch hashes + prune non-host
        # optional lock entries here; keep using upstream's derivations/module.
        # Source: local nix build FOD mismatch / HTTP/2 framing on npm-deps.
        postPatch = (oldAttrs.postPatch or "") + pruneNonHostOptionalDeps;
        npmDeps = oldAttrs.npmDeps.overrideAttrs (_: {
          postPatch = (oldAttrs.postPatch or "") + pruneNonHostOptionalDeps;
          outputHash = "sha256-+AC3DHkLQ/KU4PFTGMoEGGC4eklvE5so8UGCf7qPyaQ=";
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
