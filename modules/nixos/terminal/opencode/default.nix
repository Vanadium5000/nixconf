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
      antigravityConfigFile = ".config/opencode/antigravity.json";
      ohmyopencodeConfigFile = ".config/opencode/oh-my-opencode.json";

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
      ]
      ++ languages.packages;

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
            "opencode-antigravity-auth@latest"
            "@mohak34/opencode-notifier@latest"
            "oh-my-opencode@latest"
            # "@tarquinen/opencode-dcp@latest"
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
            "opencode"
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
            playwrite = {
              enabled = true;
              type = "local";
              command = [
                "${pkgs.playwright-mcp}/bin/mcp-server-playwright"
                "--browser=firefox"
                "--headless"
              ];
            };
            markdown_lint = {
              type = "local";
              command = [ "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.markdown-lint-mcp}/bin/markdown-lint-mcp" ];
              enabled = true;
              timeout = 10000;
            };
          };
          formatter = languages.formatter;
          lsp = languages.lsp;
          provider = providers.config;
        };
        "opencode/skill".source = skills.skillsSource + "/skill";

        "${antigravityConfigFile}".text = builtins.toJSON {
          "$schema" =
            "https://raw.githubusercontent.com/NoeFabris/opencode-antigravity-auth/main/assets/antigravity.schema.json";
          account_selection_strategy = "round-robin";
          pid_offset_enabled = true;
        };
        "${ohmyopencodeConfigFile}".text = builtins.toJSON {
          "$schema" =
            "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json";
          "google_auth" = false; # Disable conflicts
          "oracle" = {
            "model" = "gemini-3-pro-preview"; # antigravity-claude-opus-4-5-thinking
            variant = "high";
          };
          "librarian" = {
            "model" = "gemini-3-flash-preview";
            variant = "high";
          };
          "explore" = {
            "model" = "gemini-3-flash-preview";
            variant = "high";
          };
          "frontend-ui-ux-engineer" = {
            "model" = "gemini-3-pro-preview";
            variant = "high";
          };
          "document-writer" = {
            "model" = "gemini-3-flash-preview";
            variant = "high";
          };
          "multimodal-looker" = {
            "model" = "gemini-3-flash-preview";
            variant = "high";
          };
        };
      };
    };
}
