{ self, ... }:
{
  flake.nixosModules.vscodium =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      editorEdgePkgs = pkgs.unstable;
      theme = self.themes.mainTheme;
      user = config.preferences.user.username;
      opensnitchRule = name: description: operator: {
        inherit name description operator;
        created = "2026-07-09T00:00:00Z";
        updated = "2026-07-09T00:00:00Z";
        action = "allow";
        duration = "always";
        enabled = true;
        precedence = false;
        nolog = false;
      };
      simple = operand: data: {
        type = "simple";
        inherit operand data;
        sensitive = false;
        list = null;
      };
      list = operators: {
        type = "list";
        operand = "list";
        data = "";
        sensitive = false;
        list = operators;
      };

      vscodeExtensions =
        with pkgs.vscode-extensions;
        [
          # Custom theme
          (pkgs.callPackage ../../theme/vscode-extension.nix { inherit theme; })

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
        ++ (pkgs.nix4vscode.forOpenVsx [
          # AI
          # "kilocode.kilo-code" # Kilo Code - Open Source AI coding assistant for planning, building, and fixing code
          # "rooveterinaryinc.roo-cline" # Similar to Cline/Kilo Code
          # "amazonwebservices.amazon-q-vscode" # Amazon Q - Autocomplete mainly
          # "continue.continue"
          # "saoudrizwan.claude-dev" # Cline - Autonomous AI coding agent
          "fedaykindev.openchamber"

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

      settingsFile = self.lib.configFiles.known.vscodiumSettings;
      homeDirectory = config.preferences.paths.homeDirectory;
      settingsSource = self.lib.configFiles.mkConfigSourcePath {
        inherit config;
        inherit (settingsFile) relativePath storePath;
      };
      settingsBindings =
        map
          (
            editor:
            self.lib.bindMounts.mkUserPath {
              inherit pkgs user;
              sourcePath = settingsSource;
              targetFile = "${homeDirectory}/.config/${editor}/User/settings.json";
            }
          )
          [
            "VSCodium"
            "Antigravity"
          ];
      editorWaylandArgs = "--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true --wayland-text-input-version=3";

      vscodiumWayland = editorEdgePkgs.vscodium.override {
        commandLineArgs = editorWaylandArgs;
      };

      antigravityWayland = editorEdgePkgs.antigravity.override {
        commandLineArgs = editorWaylandArgs;
      };

      extensionsJson = pkgs.writeText "extensions.json" (
        pkgs.vscode-utils.toExtensionJson vscodeExtensions
      );
    in
    {
      services.opensnitch.mutableRules = lib.mkIf config.services.opensnitch.enable {
        "050-allow-vscodium-raw-githubusercontent" =
          opensnitchRule "050-allow-vscodium-raw-githubusercontent"
            "Allow the configured VSCodium package to fetch raw GitHub content."
            (list [
              (simple "process.path" "${vscodiumWayland}/lib/vscode/codium")
              (simple "dest.host" "raw.githubusercontent.com")
              (simple "dest.port" "443")
            ]);
      };

      environment.systemPackages = with pkgs; [
        vscodiumWayland
        antigravityWayland

        # The Git extension resolves the configured absolute system command;
        # install Git in this profile rather than relying on a terminal shell.
        git

        # LSPs/Dependencies
        nixd
        nil
        nixfmt # Nix formatter
        (pkgs.treefmt.withConfig {
          runtimeInputs = [ pkgs.nixfmt ];
        }) # Nixfmt-tree
        alejandra
        jq
        stylua
        luau-lsp

        kdePackages.qtdeclarative # Provides qmlls - language server for QML
        qt6Packages.qt5compat # Provides Qt5Compat.GraphicalEffects qmltypes for Quickshell scripts

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

      systemd.services = {
        vscodium-settings-bind = (builtins.elemAt settingsBindings 0).systemdService;
        antigravity-settings-bind = (builtins.elemAt settingsBindings 1).systemdService;
      };

      # Electron sees regular files, but their settings stay sourced from the
      # selected checkout/store configuration rather than writable symlinks.
      fileSystems = lib.foldl' (
        fileSystems: binding: fileSystems // binding.fileSystems
      ) { } settingsBindings;

      # Central unfree policy owns the rationale; this feature owns the opt-in.
      preferences.allowedUnfree = self.lib.nixpkgs.allowedUnfreeFor "modules/desktop/vscodium/default.nix";

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
