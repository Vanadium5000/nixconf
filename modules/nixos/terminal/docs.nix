# Nixconf Docs — static Docusaurus site generated from ./docs during rebuilds.
{ ... }:
{
  flake.nixosModules.nixconf-docs =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib)
        mkEnableOption
        mkIf
        mkOption
        types
        ;
      cfg = config.services.nixconf-docs;
      docsSrc = lib.cleanSourceWith {
        src = ../../../docs;
        filter =
          path: _type:
          let
            name = baseNameOf path;
          in
          !(builtins.elem name [
            "node_modules"
            ".docusaurus"
            "build"
          ]);
      };
      docsSite = pkgs.buildNpmPackage {
        pname = "nixconf-docs-site";
        version = "0-unstable";
        src = docsSrc;

        # Docusaurus is Node-based; importNpmLock keeps rebuilds offline and
        # tied to docs/package-lock.json instead of mutable checkout state.
        # Ref: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/javascript.section.md#importnpmlock
        npmDeps = pkgs.importNpmLock {
          npmRoot = docsSrc;
        };
        npmConfigHook = pkgs.importNpmLock.npmConfigHook;
        npmFlags = [ "--legacy-peer-deps" ];

        env.DISABLE_VERSION_CHECK = "true";

        installPhase = ''
          runHook preInstall

          mkdir -p "$out/share/nixconf-docs"
          cp -r build/. "$out/share/nixconf-docs/"

          runHook postInstall
        '';
      };
    in
    {
      options.services.nixconf-docs = {
        enable = mkEnableOption "static Nixconf Docusaurus documentation";

        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Address nginx listens on for the generated docs site.";
        };

        port = mkOption {
          type = types.port;
          default = 8090;
          description = "Port for the generated docs site.";
        };

        openFirewall = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to open the docs port in the firewall.";
        };

        package = mkOption {
          type = types.package;
          readOnly = true;
          default = docsSite;
          description = "Built static Docusaurus documentation artifact.";
        };
      };

      config = mkIf cfg.enable {
        services.nginx = {
          enable = true;
          virtualHosts.nixconf-docs = {
            listen = [
              {
                addr = cfg.host;
                port = cfg.port;
              }
            ];
            root = "${cfg.package}/share/nixconf-docs";
            locations."/" = {
              index = "index.html";
              tryFiles = "$uri $uri/ /index.html";
            };
          };
        };

        networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
      };
    };
}
