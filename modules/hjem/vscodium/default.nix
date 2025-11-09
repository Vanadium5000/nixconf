{
  flake.nixosModules.extra_hjem =
    {
      pkgs,
      config,
      ...
    }:
    let
      user = config.preferences.user.username;
    in
    {
      environment.systemPackages = with pkgs; [
        (vscode-with-extensions.override {
          vscode = vscodium;
          vscodeExtensions = with vscode-extensions; [
            # Rust
            rust-lang.rust-analyzer
            vadimcn.vscode-lldb # Rust debugging

            # TOML
            tamasfe.even-better-toml # Support for Cargo.toml

            # YAML
            redhat.vscode-yaml

            # Python
            ms-python.python
            ms-python.debugpy
            ms-python.black-formatter
            ms-python.mypy-type-checker
            ms-python.pylint

            # Web dev
            bradlc.vscode-tailwindcss
            esbenp.prettier-vscode
            # svelte.svelte-vscode # Svelte

            # Go
            golang.go

            # Nix
            jnoortheen.nix-ide

            # General
            eamodio.gitlens
            ms-azuretools.vscode-containers
            pkief.material-icon-theme
            # usernamehw.errorlens # Improves error highlighting
            fill-labs.dependi # Helps manage dependencies
            #streetsidesoftware.code-spell-checker
            gruntfuggly.todo-tree # Show TODOs, FIXMEs, etc. comment tags in a tree view
            mkhl.direnv # Direnv for VSCodium

            # AI
            kilocode.kilo-code # Kilo Code - Open Source AI coding assistant for planning, building, and fixing code
            # amazonwebservices.amazon-q-vscode # Amazon Q - Autocomplete mainly
            # continue.continue
            # saoudrizwan.claude-dev # Cline - Autonomous AI coding agent
          ];
        })

        # LSPs/Dependencies
        nixd
        nil
        nixfmt-rfc-style # Nixfmt
        nixfmt-tree # Nixfmt-tree
        alejandra
      ];

      hjem.users.${user} = {
        files.".config/VSCodium/User/settings.json".source =
          "${config.preferences.configDirectory}/modules/hjem/vscodium/settings.json";
      };

      # FIXME: "fill-labs.dependi" is UNFREE
      preferences.allowedUnfree = [ "vscode-extension-fill-labs-dependi" ];

      # Persist settings & extensions
      impermanence.home.cache.directories = [
        ".config/VSCodium"
        ".vscode-oss/extensions"
      ];
    };
}
