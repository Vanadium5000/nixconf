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

          # Lua
          sumneko.lua

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
          "kilocode.kilo-code" # Kilo Code - Open Source AI coding assistant for planning, building, and fixing code
          # "rooveterinaryinc.roo-cline" # Similar to Cline/Kilo Code
          # "amazonwebservices.amazon-q-vscode" # Amazon Q - Autocomplete mainly
          # "continue.continue"
          # "saoudrizwan.claude-dev" # Cline - Autonomous AI coding agent

          # BunJS
          "oven.bun-vscode"

          # QML - Quickshell
          "theqtcompany.qt-qml"
          "theqtcompany.qt-core"
        ]);

      inherit (self) colors;
    in
    {
      environment.systemPackages = with pkgs; [
        (vscode-with-extensions.override {
          vscode = vscodium;
          inherit vscodeExtensions;
        })
        (vscode-with-extensions.override {
          vscode = unstable.antigravity;
          inherit vscodeExtensions;
        })

        # LSPs/Dependencies
        nixd
        nil
        nixfmt-rfc-style # Nixfmt
        nixfmt-tree # Nixfmt-tree
        alejandra

        kdePackages.qtdeclarative # Provides qmlls - language server for QML
      ];

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
      ];
    };
}
