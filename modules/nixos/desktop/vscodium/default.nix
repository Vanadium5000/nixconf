{ self, ... }:
{
  flake.nixosModules.vscodium =
    {
      pkgs,
      config,
      ...
    }:
    let
      user = config.preferences.user.username;

      vscodeExtensions =
        with pkgs.vscode-extensions;
        [
          # Custom theme
          (pkgs.callPackage ./_theme-extension.nix { inherit colors; })

          # Rust
          # rust-lang.rust-analyzer
          # vadimcn.vscode-lldb # Rust debugging

          # TOML
          tamasfe.even-better-toml # Support for Cargo.toml

          # YAML
          redhat.vscode-yaml

          # Python
          # ms-python.python
          # ms-python.debugpy
          # ms-python.black-formatter
          # ms-python.mypy-type-checker
          # ms-python.pylint

          # Web dev
          bradlc.vscode-tailwindcss
          esbenp.prettier-vscode
          # svelte.svelte-vscode # Svelte

          # Go
          # golang.go

          # Nix
          jnoortheen.nix-ide

          # General
          eamodio.gitlens
          # ms-azuretools.vscode-containers
          pkief.material-icon-theme
          # usernamehw.errorlens # Improves error highlighting
          fill-labs.dependi # Helps manage dependencies
          #streetsidesoftware.code-spell-checker
          gruntfuggly.todo-tree # Show TODOs, FIXMEs, etc. comment tags in a tree view
          mkhl.direnv # Direnv for VSCodium
        ]
        # Fetch extensions less declaritively for any not in nixpkgs or that need to be kept up to date
        ++ (pkgs.nix4vscode.forVscode [
          # AI
          # "kilocode.kilo-code" # Kilo Code - Open Source AI coding assistant for planning, building, and fixing code
          # "rooveterinaryinc.roo-cline" # Similar to Cline/Kilo Code
          # "amazonwebservices.amazon-q-vscode" # Amazon Q - Autocomplete mainly
          # "continue.continue"
          # "saoudrizwan.claude-dev" # Cline - Autonomous AI coding agent

          # BunJS
          "oven.bun-vscode"

          # QML - Quickshell
          "theqtcompany.qt-qml"
          "theqtcompany.qt-core"

          # Luau
          # "nightrains.robloxlsp"
          "johnnymorganz.luau-lsp"
          "johnnymorganz.stylua"

          # Markdown
          "davidanson.vscode-markdownlint"
        ]);

      inherit (self) colors;

      extensionsJson = pkgs.writeText "extensions.json" (
        pkgs.vscode-utils.toExtensionJson vscodeExtensions
      );
    in
    {
      environment.systemPackages = with pkgs; [
        vscodium
        unstable.antigravity

        # LSPs/Dependencies
        nixd
        nil
        nixfmt-rfc-style # Nixfmt
        (pkgs.treefmt.withConfig {
          runtimeInputs = [ pkgs.nixfmt-rfc-style ];
        }) # Nixfmt-tree
        alejandra
        jq

        kdePackages.qtdeclarative # Provides qmlls - language server for QML

        # Fix VSCode keyring
        gnome-keyring
        libsecret # contains secret-tool + provides the org.freedesktop.secrets service
        seahorse # optional GUI to see/manage keyrings (very useful for debugging)
      ];

      # Enable Gnome keyring
      services.gnome.gnome-keyring.enable = true;

      system.activationScripts.vscodium-extensions = {
        text = ''
          # Cleanup and setup extension directories
          for dir in "/home/${user}/.vscode-oss/extensions" "/home/${user}/.antigravity/extensions"; do
            mkdir -p "$dir"
            chown ${user}:users "$dir"
            
            # Link extensions
            for ext in ${toString vscodeExtensions}; do
              if [ -d "$ext/share/vscode/extensions" ]; then
                find "$ext/share/vscode/extensions" -mindepth 1 -maxdepth 1 -print0 | while IFS= read -r -d "" ext_source; do
                  ext_name=$(basename "$ext_source")
                  target="$dir/$ext_name"
                  
                  # Force replace key extensions
                  if [ -e "$target" ] || [ -h "$target" ]; then
                    rm -rf "$target"
                  fi
                  # Copy instead of symlink to allow write access (fixes EROFS for some extensions like Roblox LSP)
                  cp -Lr --no-preserve=mode "$ext_source" "$target"
                done
              fi
            done
            
            # Update extensions.json
            # Prepare new extensions JSON with mutable paths
            ${pkgs.jq}/bin/jq --arg dir "$dir" 'map(.location.path = ($dir + "/" + (.location.path | split("/") | last)) | .location.fsPath = ($dir + "/" + (.location.fsPath | split("/") | last)))' "${extensionsJson}" > "$dir/new_extensions.json"

            # Update extensions.json
            if [ -f "$dir/extensions.json" ]; then
               # Merge existing with new (new wins for same ID, user extensions kept)
               ${pkgs.jq}/bin/jq -s '.[1] as $new | (.[0] | map(select(.identifier.id as $id | $new | map(.identifier.id) | index($id) | not))) + $new' "$dir/extensions.json" "$dir/new_extensions.json" > "$dir/extensions.json.tmp" && mv "$dir/extensions.json.tmp" "$dir/extensions.json"
            else
               mv "$dir/new_extensions.json" "$dir/extensions.json"
            fi
            rm -f "$dir/new_extensions.json"
            chown ${user}:users "$dir/extensions.json"
            
            chown -R ${user}:users "$dir" --no-dereference
          done
        '';
        deps = [ "users" ];
      };

      hjem.users.${user} = {
        files.".config/VSCodium/User/settings.json".source =
          "${config.preferences.configDirectory}/modules/nixos/desktop/vscodium/settings.json";
        files.".config/Antigravity/User/settings.json".source =
          "${config.preferences.configDirectory}/modules/nixos/desktop/vscodium/settings.json";
      };

      # FIXME: "fill-labs.dependi" is UNFREE
      preferences.allowedUnfree = [
        "vscode-extension-fill-labs-dependi"

        # Google Antigravity
        "antigravity"
        "antigravity-with-extensions"
      ];

      # Persist settings & extensions
      impermanence.home.cache.directories = [
        ".config/VSCodium"
        ".config/Antigravity"
        ".vscode-oss"
        ".antigravity" # Editor data, e.g. extensions
        ".gemini" # AI data, e.g. convos
      ];
    };
}
