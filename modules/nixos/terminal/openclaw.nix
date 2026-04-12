{ self, inputs, ... }:
{
  flake.nixosModules.openclaw =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      inherit (lib) mkEnableOption mkIf;
      cfg = config.services.openclaw;
    in
    {
      imports = [
        inputs.nix-openclaw.nixosModules.openclaw-gateway
      ];

      options.services.openclaw = {
        enable = mkEnableOption "OpenClaw AI assistant gateway";
      };

      config = mkIf cfg.enable {
        services.openclaw-gateway = {
          enable = true;
          package = inputs.nix-openclaw.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-gateway;
          # Keep 3100 to match existing reverse-proxy/public URL wiring.
          port = 3100;
          # Upstream asserts the config lives under /etc, but the gateway also
          # writes temporary siblings next to the file at startup. Put it in a
          # dedicated writable subdirectory so both constraints are satisfied.
          configPath = "/etc/openclaw/state/openclaw.json";
          # Upstream module creates user/group/stateDir defaults; we override only
          # provider config and a writable config path that still satisfies its
          # /etc assertion.
          config = {
            gateway = {
              mode = "local";
            };
            models = {
              mode = "merge";
              providers.cliproxyapi = {
                baseUrl = "http://127.0.0.1:8317/v1";
                apiKey = self.secrets.CLIPROXYAPI_KEY;
                api = "openai-completions";
                # Optional: specify models if auto-discovery doesn't work well
                models = [
                  {
                    id = "gemini-3-flash";
                    name = "Gemini 3 Flash";
                    contextWindow = 1048576;
                    maxTokens = 65536;
                  }
                ];
              };
            };
            # Default to cliproxyapi
            agents.defaults.model.primary = "cliproxyapi/gemini-3-flash";
          };

          environment = {
            OPENCLAW_NIX_MODE = "1";
          };
        };

        # Persist config, workspace, and memory across reboots
        impermanence.nixos.directories = [
          {
            directory = "/var/lib/openclaw";
            user = "openclaw";
            group = "openclaw";
            mode = "0750";
          }
        ];

        # The gateway writes a temporary file next to configPath before swapping
        # it into place, so the parent directory must be writable by openclaw.
        systemd.tmpfiles.rules = [
          "d /etc/openclaw/state 0750 openclaw openclaw -"
        ];
      };
    };
}
