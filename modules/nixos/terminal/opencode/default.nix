{ inputs, self, ... }:
{
  flake.nixosModules.opencode =
    {
      pkgs,
      config,
      ...
    }:
    let
      user = config.preferences.user.username;
      languages = import ./_languages.nix { inherit pkgs self; };
      providers = import ./_providers.nix;
      skills = import ./_skills.nix { inherit pkgs; };

      opencode = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.default;

      opencodeEnv = pkgs.buildEnv {
        name = "opencode-env";
        paths = languages.packages ++ skills.packages;
      };

      opencodeInitScript = pkgs.writeShellScript "opencode-init" ''
        mkdir -p "$HOME/.local/cache/opencode/node_modules/@opencode-ai"
        mkdir -p "$HOME/.config/opencode/node_modules/@opencode-ai"
        if [ -d "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" ]; then
          if [ ! -L "$HOME/.local/cache/opencode/node_modules/@opencode-ai/plugin" ]; then
            ln -sf "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" \
                   "$HOME/.local/cache/opencode/node_modules/@opencode-ai/plugin"
          fi
        fi
        exec ${opencode}/bin/opencode "$@"
      '';

      opencodeWrapped =
        pkgs.runCommand "opencode-wrapped"
          {
            buildInputs = [ pkgs.makeWrapper ];
          }
          ''
            mkdir -p $out/bin
            makeWrapper ${opencodeInitScript} $out/bin/opencode \
              --prefix PATH : ${opencodeEnv}/bin \
              --set OPENCODE_LIBC ${pkgs.glibc}/lib/libc.so.6
          '';
      configFile = ".config/opencode/config.json";

      # Persistence configuration using bind mount for reliability
      accountsPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "opencode-accounts.json";
        targetFile = "/home/${user}/.config/opencode/antigravity-accounts.json";
        defaultContent = "{}";
      };
    in
    {
      environment.systemPackages = [
        opencodeWrapped
      ];

      # Setup script to ensure files exist before mount
      system.activationScripts.opencode-persistence = {
        text = accountsPersistence.activationScript;
        deps = [ "users" ];
      };

      # Bind mount for reliable persistence (apps can't overwrite)
      fileSystems = accountsPersistence.fileSystems;
      hjem.users.${user}.files = {
        "${configFile}".text = builtins.toJSON {
          "$schema" = "https://opencode.ai/config.json";
          plugin = [
            "opencode-antigravity-auth@beta"
            "@mohak34/opencode-notifier@latest"
          ];
          small_model = "google/gemma-3n-e4b-it:free";
          autoupdate = false;
          share = "disabled";
          disabled_providers = [
            "amazon-bedrock"
            "anthropic"
            "azure-openai"
            "azure-cognitive-services"
            "baseten"
            "cerebras"
            "cloudflare-ai-gateway"
            "cortecs"
            "deepseek"
            "deep-infra"
            "fireworks-ai"
            "github-copilot"
            "google-vertex-ai"
            "groq"
            "hugging-face"
            "helicone"
            "llama.cpp"
            "io-net"
            "lmstudio"
            "moonshot-ai"
            "nebius-token-factory"
            "ollama"
            "ollama-cloud"
            "openai"
            "opencode-zen"
            "sap-ai-core"
            "ovhcloud-ai-endpoints"
            "together-ai"
            "venice-ai"
            "xai"
            "zai"
            "zenmux"
          ];
          enabled_providers = [
            "openrouter"
            "google"
          ];
          mcp = {
            gh_grep = {
              type = "remote";
              url = "https://mcp.grep.app/";
              enabled = true;
              timeout = 10000;
            };
            deepwiki = {
              type = "remote";
              url = "https://mcp.deepwiki.com/mcp";
              enabled = true;
              timeout = 10000;
            };
            context7 = {
              type = "remote";
              url = "https://mcp.context7.com/mcp";
              enabled = true;
              timeout = 10000;
            };
            daisyui = {
              type = "local";
              command = [ "${self.packages.${pkgs.stdenv.hostPlatform.system}.daisyui-mcp}/bin/daisyui-mcp" ];
              enabled = true;
              timeout = 10000;
            };
          };
          formatter = languages.formatter;
          lsp = languages.lsp;
          provider = providers.config;
        };
        "opencode/skill".source = skills.skillsSource + "/skill";
      };
    };
}
