{ self, inputs, ... }:
{
  flake.nixosModules.openclaw =
    {
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
          # Port 3100 was zeroclaw's, we keep it for now but bind to localhost
          port = 3100;
          # Upstream module creates user/group/stateDir/configPath by default
          # We just need to configure the provider
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
      };
    };
}
