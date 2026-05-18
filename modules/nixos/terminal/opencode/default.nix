{ inputs, self, ... }:
{
  flake.nixosModules.opencode =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      # These path helpers are reused across generated configs, persistence, and
      # the TUI wrapper, so keep them close to the top-level module inputs.
      user = config.preferences.user.username;
      homeDirectory = config.preferences.paths.homeDirectory;
      configDirectory = config.preferences.paths.configDirectory;
      publicBaseDomain = self.secrets.PUBLIC_BASE_DOMAIN;

      # Existing adjacent helpers already split stable data domains cleanly.
      # Keep those imports, but keep the runtime assembly in this file so future
      # contract-sensitive changes stay visible in one place.
      languages = import ./_languages.nix { inherit pkgs self; };
      providers = import ./_providers.nix {
        inherit self lib;
      };
      pluginsConfig = import ./_plugins.nix;
      categoriesConfig = import ./_categories.nix { inherit lib; };
      opencode = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.opencode;

      # OpenCode scans `~/.config/opencode/skills/<name>/SKILL.md`; install each
      # skill file explicitly so activation can preserve the expected tree shape.
      # Source: https://opencode.ai/docs/skills/
      opencodeSkillFiles = builtins.listToAttrs (
        map (skillName: {
          name = ".config/opencode/skills/${skillName}/SKILL.md";
          value = {
            source = ./skill + "/${skillName}/SKILL.md";
            type = "copy";
            permissions = "0644";
          };
        }) (lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skill)))
      );

      # TODO: SETUP SKILLS BETTER
      # mattpocockSkills = pkgs.customPackages.mattpocock-skills;
      # mattpocockSkillFiles =
      #   let
      #     sourceRoot = "${mattpocockSkills}/share/opencode/skills";
      #     listRelativeFiles =
      #       dir:
      #       lib.flatten (
      #         lib.mapAttrsToList (
      #           name: type:
      #           if type == "regular" then
      #             [ name ]
      #           else if type == "directory" then
      #             map (child: "${name}/${child}") (listRelativeFiles (dir + "/${name}"))
      #           else
      #             [ ]
      #         ) (builtins.readDir dir)
      #       );
      #     skillNames = lib.attrNames (
      #       lib.filterAttrs (_: type: type == "directory") (builtins.readDir sourceRoot)
      #     );
      #   in
      #   builtins.listToAttrs (
      #     lib.flatten (
      #       map (
      #         skillName:
      #         map (relativeFile: {
      #           name = ".config/opencode/skills/${skillName}/${relativeFile}";
      #           value = {
      #             source = sourceRoot + "/${skillName}/${relativeFile}";
      #             type = "copy";
      #             permissions = "0644";
      #           };
      #         }) (listRelativeFiles (sourceRoot + "/${skillName}"))
      #       ) skillNames
      #     )
      #   );

      # state.json is repo-owned so model/category choices survive wrapper runs
      # and can be reviewed/committed like any other configuration change.
      stateFile = ./state.json;
      state = categoriesConfig.mkState { inherit stateFile; };

      # MCP server configuration is shared by the global OpenCode config and the
      # project template generator, so keep one source of truth here.
      mcpConfig = {
        gh_grep = {
          # grep.app is the default public code-search MCP used across this repo.
          type = "remote";
          url = "https://mcp.grep.app/";
          enabled = true;
          timeout = 20000;
        };

        context7 = {
          # Context7 keeps API docs current without bundling snapshots locally.
          type = "remote";
          url = "https://mcp.context7.com/mcp";
          enabled = true;
          timeout = 20000;
        };

        markdown_lint = {
          # Enabled globally so repo guidance and generated plans stay lintable.
          type = "local";
          command = [
            "${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.markdown-lint-mcp}/bin/markdown-lint-mcp"
          ];
          enabled = true;
          timeout = 10000;
        };

        # Remote tool: High-quality parallel web search with deep research capabilities.
        # Already declared by Oh-My-OpenAgent.
        # websearch = {
        #   type = "remote";
        #   url = "https://mcp.exa.ai/mcp?exaApiKey=${self.secrets.EXA_API_KEY}&tools=web_search_exa,deep_search_exa,get_code_context_exa,crawling_exa,deep_researcher_start,deep_researcher_check";
        #   enabled = true;
        #   timeout = 30000;
        # };

        image_gen = {
          # Resolve the first image-capable model at runtime so model sync stays
          # authoritative and repo-owned modality patches apply immediately
          # without requiring a rebuild.
          type = "local";
          command = [
            (pkgs.writeShellScript "image-gen-mcp-wrapper" ''
              export OMNIROUTE_OPENCODE_API_KEY="${self.secrets.OMNIROUTE_OPENCODE_API_KEY}"
              export OMNIROUTE_BASE_URL="https://omniroute.${publicBaseDomain}/v1"
              MODELS_FILE="${configDirectory}/modules/nixos/terminal/opencode/models.json"
              PATCHES_FILE="${configDirectory}/modules/nixos/terminal/opencode/_model-local-patches.json"

              # Prefer the first runtime-effective model that advertises image output.
              # Source of truth is the repo models cache plus repo-owned JSON patches.
              if [ -f "$PATCHES_FILE" ] && [ -s "$PATCHES_FILE" ]; then
                IMAGE_MODEL="$(${pkgs.jq}/bin/jq -r --slurpfile patches "$PATCHES_FILE" '
                  first(
                    def normalize_model:
                      . as $model
                      | ($model | del(.context, .output))
                        + (if (($model.context // null) != null) or (($model.output // null) != null) then
                            {
                              limit: (($model.limit // {})
                                + (if (($model.context // null) != null) then { context: $model.context } else {} end)
                                + (if (($model.output // null) != null) then { output: $model.output } else {} end))
                            }
                          else
                            {}
                          end);
                    (.providers.omniroute.models // {}) as $models
                    | $models * (($patches[0] // {}) | with_entries(select($models[.key] != null)))
                    | map_values(normalize_model)
                    | to_entries[]
                    | select(((.value.modalities.output // []) | index("image")) != null)
                    | "omniroute/\(.key)"
                  ) // empty
                ' "$MODELS_FILE")"
              else
                export IMAGE_MODEL="$(${pkgs.jq}/bin/jq -r '
                  first(
                    (.providers.omniroute.models // {})
                    | to_entries[]
                    | select(((.value.modalities.output // []) | index("image")) != null)
                    | "omniroute/\(.key)"
                  ) // empty
                ' "$MODELS_FILE")"
              fi

              exec ${inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.image-gen-mcp}/bin/image-gen-mcp
            '')
          ];
          enabled = true;
          timeout = 60000;
        };
      };

      # Base configuration containing non-dynamic parts
      baseConfig = {
        "$schema" = "https://opencode.ai/config.json";
        plugin = pluginsConfig.plugins;
        small_model = "omniroute/kilocode/kilo-auto/free";
        autoupdate = false;
        share = "disabled";
        permission = {
          read = {
            "*.redacted.*" = "deny";
          };
        };
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
          "opencode"
          "omniroute"
        ];
        mcp = mcpConfig;
        inherit (languages) formatter lsp;
        provider = providers.config;
      };

      # Generate initial fallback config so opencode has *something* to launch with if modified
      initialConfig = baseConfig;

      ohMyOpencodeConfig = categoriesConfig.mkOhMyConfig { inherit state; };

      opencodeModelsMetadata = categoriesConfig.mkMenuMetadata // {
        menu = categoriesConfig.mkMenuMetadata.menu // {
          reasoningEffortHeader = "Select reasoning effort for this model";
        };
      };

      # The Obsidian skill invokes this wrapper instead of a raw MCP command so
      # each coding project is confined to ~/Vault/Projects/<slug>, never the
      # full vault. obsidian-mcp accepts vault roots as positional arguments:
      # https://www.npmjs.com/package/obsidian-mcp
      # Pin 1.0.6 because its positional vault-root contract is part of this
      # wrapper's safety boundary; update deliberately after re-verifying it.
      opencodeObsidianProjectMcp = pkgs.writeShellScriptBin "opencode-obsidian-project-mcp" (
        lib.concatStringsSep "\n" [
          "set -eu"
          ""
          ''project_root="$PWD"''
          ''search_dir="$PWD"''
          ""
          ''while [ "$search_dir" != "/" ]; do''
          ''if [ -d "$search_dir/.git" ] || [ -f "$search_dir/.git" ]; then''
          ''project_root="$search_dir"''
          "    break"
          "  fi"
          ""
          ''search_dir="$(${pkgs.coreutils}/bin/dirname "$search_dir")"''
          "done"
          ""
          ''project_slug="$(${pkgs.coreutils}/bin/basename "$project_root")"''
          ""
          ''project_slug="$(printf '%s' "$project_slug" | ${pkgs.gnused}/bin/sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//')"''
          ""
          ''if [ -z "$project_slug" ] || [ "$project_slug" = "." ] || [ "$project_slug" = ".." ]; then''
          ''printf 'Could not derive a safe Obsidian project slug from %s\n' "$PWD" >&2''
          "  exit 1"
          "fi"
          ""
          ''project_vault="$HOME/Vault/Projects/$project_slug"''
          ''if [ -L "$project_vault" ]; then''
          ''printf 'Refusing symlinked Obsidian project vault: %s\n' "$project_vault" >&2''
          "  exit 1"
          "fi"
          ""
          ''${pkgs.coreutils}/bin/mkdir -p \''
          ''"$project_vault/.obsidian" \''
          ''"$project_vault/architecture" \''
          ''"$project_vault/decisions" \''
          ''"$project_vault/docs" \''
          ''"$project_vault/open-questions" \''
          ''"$project_vault/research" \''
          ''"$project_vault/runbooks" \''
          ''"$project_vault/session-logs"''
          ""
          ''if [ ! -f "$project_vault/.obsidian/app.json" ]; then''
          ''printf '{}\n' > "$project_vault/.obsidian/app.json"''
          "fi"
          ""
          ''if [ ! -f "$project_vault/_index.md" ]; then''
          ''${pkgs.coreutils}/bin/cat > "$project_vault/_index.md" <<EOF''
          "---"
          "type: project-index"
          "project: $project_slug"
          "repo: \"$project_root\""
          "tags:"
          "  - project/$project_slug"
          "  - opencode"
          "---"
          ""
          "# $project_slug"
          ""
          "Project-scoped Obsidian workspace for OpenCode agents. Agents should keep durable project documentation, decisions, research, runbooks, and session notes under this directory only."
          "EOF"
          "fi"
          ""
          ''exec ${pkgs.nodejs}/bin/npx -y obsidian-mcp@1.0.6 "$project_vault"''
        ]
      );

      # Templates live in the store so the TUI can switch project bootstraps
      # without mutating repo files or recomputing JSONC snippets by hand.
      mcpTemplates =
        let
          allMcpNames = lib.attrNames mcpConfig;

          mkTemplateJsonC =
            _: enabledMcpNames:
            let
              globallyEnabledNotInTemplate = lib.filterAttrs (
                name: cfg: (cfg.enabled or false) && !(builtins.elem name enabledMcpNames)
              ) mcpConfig;

              availableNotInTemplate = lib.filterAttrs (
                name: cfg: !(builtins.elem name enabledMcpNames) && !(cfg.enabled or false)
              ) mcpConfig;

              globalNames = lib.attrNames globallyEnabledNotInTemplate;
              availableNames = lib.attrNames availableNotInTemplate;
              allDataNames = globalNames ++ availableNames ++ enabledMcpNames;
              lastIdx = lib.length allDataNames - 1;

              mkLine =
                i: text:
                let
                  comma = if i == lastIdx then "" else ",";
                in
                "    ${text}${comma}";

              globalSection =
                if globalNames == [ ] then
                  [ ]
                else
                  [ "    // Globally enabled by default - disable if not needed" ]
                  ++ (lib.imap0 (i: name: mkLine i "// \"${name}\": { \"enabled\": false }") globalNames);

              availableSection =
                if availableNames == [ ] then
                  [ ]
                else
                  [ "    // Available: uncomment to enable" ]
                  ++ (lib.imap0 (
                    i: name: mkLine (i + lib.length globalNames) "// \"${name}\": { \"enabled\": true }"
                  ) availableNames);

              enabledSection = lib.imap0 (
                i: name:
                mkLine (i + lib.length globalNames + lib.length availableNames) "\"${name}\": { \"enabled\": true }"
              ) enabledMcpNames;

              result =
                globalSection
                ++ lib.optional (globalSection != [ ] && (availableSection != [ ] || enabledSection != [ ])) ""
                ++ availableSection
                ++ lib.optional (availableSection != [ ] && enabledSection != [ ]) ""
                ++ enabledSection;
            in
            "{\n  \"mcp\": {\n${lib.concatStringsSep "\n" result}\n  }\n}";
        in
        {
          "All MCPs" = mkTemplateJsonC "All MCPs" allMcpNames;
          "No MCPs" = mkTemplateJsonC "No MCPs" [ ];
          "Custom MCP File" = mkTemplateJsonC "Custom MCP File" [ ];
        };

      configVariantsDir = pkgs.runCommand "opencode-configs" { } ''
        mkdir -p $out/templates
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: value:
            let
              safeName = lib.replaceStrings [ " " "/" ] [ "_" "_" ] name;
            in
            ''
              cat > "$out/templates/${safeName}.json" << 'EOF'
              ${value}
              EOF
            ''
          ) mcpTemplates
        )}
      '';

      # The implementation lives in modules/nixos/scripts/models.nix so OMP and
      # OpenCode share one model sync path while preserving local mutable files.
      modelsCommand = self.packages.${pkgs.stdenv.hostPlatform.system}.models;

      opencodeEnv = pkgs.buildEnv {
        name = "opencode-env";
        paths = languages.packages ++ [
          pkgs.libreoffice
          opencodeObsidianProjectMcp
          pkgs.python3
          pkgs.stdenv.cc
          pkgs.gnumake
        ];
      };

      # The wrapper keeps OpenCode usable on impermanent systems by recreating
      # cache/plugin paths and syncing generated config before launch.
      opencodeInitScript = pkgs.writeShellScript "opencode-init" ''
        mkdir -p "$HOME/.local/cache/opencode/node_modules/@opencode-ai"
        mkdir -p "$HOME/.config/opencode/node_modules/@opencode-ai"
        if [ -d "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" ]; then
          if [ ! -L "$HOME/.local/cache/opencode/node_modules/@opencode-ai/plugin" ]; then
            ln -sf "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" \
                   "$HOME/.local/cache/opencode/node_modules/@opencode-ai/plugin"
          fi
        fi

        models sync-config >/dev/null 2>&1 || true

        exec ${opencode}/bin/opencode "$@"
      '';

      opencodeWrapped = pkgs.runCommand "opencode-wrapped" { buildInputs = [ pkgs.makeWrapper ]; } ''
        mkdir -p $out/bin
        makeWrapper ${opencodeInitScript} $out/bin/opencode \
          --prefix PATH : ${opencodeEnv}/bin \
          --set OPENCODE_LIBC ${pkgs.glibc}/lib/libc.so.6
      '';

      # Bind mounts are used instead of symlinks so applications see regular
      # paths even on impermanent roots and cannot replace persistence with a
      # fresh file by accident.
      toolsPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "antigravity_tools";
        targetFile = "${homeDirectory}/.antigravity_tools";
        isDirectory = true;
      };

      opencodePersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "opencode";
        targetFile = "${homeDirectory}/.local/share/opencode";
        isDirectory = true;
      };

      opencodeMemPersistence = self.lib.persistence.mkPersistent {
        method = "bind";
        inherit user;
        fileName = "opencode-mem";
        targetFile = "${homeDirectory}/.opencode-mem";
        isDirectory = true;
      };

      opencodeMemConfig = {
        storagePath = "${homeDirectory}/.opencode-mem/data";
        embeddingModel = "Xenova/nomic-embed-text-v1";
        memoryProvider = "openai-chat";
        memoryModel = state.categories.deep.model;
        memoryApiUrl = "https://omniroute.${publicBaseDomain}/v1";
        memoryApiKey = self.secrets.OMNIROUTE_OPENCODE_API_KEY;
        autoCaptureEnabled = true;
        webServerEnabled = true;
        webServerPort = 4747;
        chatMessage = {
          enabled = true;
          maxMemories = 3;
          injectOn = "first";
        };
      };

    in
    {
      environment.systemPackages = [
        opencodeWrapped
        modelsCommand
        opencodeObsidianProjectMcp
      ]
      ++ languages.packages;

      # Setup script ensures mount targets exist before the bind mounts are
      # activated, which keeps impermanence boot ordering predictable.
      system.activationScripts.opencode-persistence = {
        text =
          toolsPersistence.activationScript
          + opencodePersistence.activationScript
          + opencodeMemPersistence.activationScript;
        deps = [ "users" ];
      };

      fileSystems =
        toolsPersistence.fileSystems
        // opencodePersistence.fileSystems
        // opencodeMemPersistence.fileSystems;

      system.activationScripts.opencode-user-files = {
        text = self.lib.userFiles.mkActivationScript {
          inherit user homeDirectory;
          inherit pkgs;
          files = {
            ".config/opencode/config.json" = {
              text = builtins.toJSON initialConfig;
              type = "copy";
              permissions = "0600";
            };

            ".config/opencode/oh-my-opencode.jsonc" = {
              text = builtins.toJSON ohMyOpencodeConfig;
              type = "copy";
              permissions = "0600";
            };

            # Compatibility alias used by some OpenCode plugin/runtime paths.
            # Keep this synced with oh-my-opencode.jsonc to avoid stale model picks.
            ".config/opencode/oh-my-openagent.jsonc" = {
              text = builtins.toJSON ohMyOpencodeConfig;
              type = "copy";
              permissions = "0600";
            };

            ".config/opencode/command" = {
              source = ./command;
              type = "copy";
              permissions = "0755";
            };

            ".config/opencode/plugin" = {
              source = ./plugin;
              type = "copy";
              permissions = "0755";
            };

            ".config/opencode/AGENTS.md" = {
              source = ./_AGENTS.md;
              type = "copy";
              permissions = "0644";
            };

            ".config/opencode/package.json" = {
              source = ./_package.json;
              type = "copy";
              permissions = "0644";
            };

            ".config/opencode/opencode-mem.jsonc" = {
              text = builtins.toJSON opencodeMemConfig;
              type = "copy";
              permissions = "0644";
            };

            # Shared `models` reads OpenCode bases from regular files so local
            # experiments can edit them, while activation refreshes from this module.
            # Source: OpenCode config schema https://opencode.ai/docs/config/.
            ".config/models/opencode/opencode-base.json" = {
              text = builtins.toJSON baseConfig;
              type = "copy";
              permissions = "0644";
            };

            ".config/models/opencode/oh-my-opencode-base.json" = {
              text = builtins.toJSON ohMyOpencodeConfig;
              type = "copy";
              permissions = "0644";
            };

            ".config/models/opencode/opencode-mem-base.json" = {
              text = builtins.toJSON opencodeMemConfig;
              type = "copy";
              permissions = "0644";
            };

            ".config/models/opencode/models-metadata.json" = {
              text = builtins.toJSON opencodeModelsMetadata;
              type = "copy";
              permissions = "0644";
            };

            # Project template copies are intentionally mutable for trial runs;
            # `models init` consumes these by basename from ~/.config/models/opencode/templates.
            # Source templates: modules/nixos/terminal/opencode configVariantsDir.
            ".config/models/opencode/templates" = {
              source = "${configVariantsDir}/templates";
              type = "copy";
              permissions = "0644";
            };
          }
          # // mattpocockSkillFiles # TODO: SETUP SKILLS BETTER
          // opencodeSkillFiles;
        };
        deps = [ "users" ];
      };
    };
}
