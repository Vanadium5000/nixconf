{
  self,
  lib,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;
in
{
  flake.nixosModules.fresh =
    {
      config,
      pkgs,
      ...
    }:
    let
      user = config.preferences.user.username;
      homeDirectory = config.preferences.paths.homeDirectory;
      freshConfig = {
        version = 1;
        theme = "dark";
        check_for_updates = false;
        editor = {
          line_numbers = true;
          relative_line_numbers = false;
          highlight_current_line = true;
          line_wrap = true;
          wrap_indent = true;
          page_width = 100;
          use_tabs = false;
          tab_size = 2;
          auto_indent = true;
          trim_trailing_whitespace_on_save = true;
          ensure_final_newline_on_save = true;
          enable_inlay_hints = true;
          diagnostics_inline_text = false;
          mouse_hover_enabled = true;
          auto_save_enabled = false;
          recovery_enabled = true;
        };
        file_explorer = {
          respect_gitignore = true;
          show_hidden = true;
          show_gitignored = false;
          custom_ignore_patterns = [
            ".git"
            "node_modules"
            "result"
            "result-*"
          ];
          width = 0.3;
        };
        file_browser.show_hidden = true;
        clipboard = {
          use_osc52 = true;
          use_system_clipboard = true;
        };
        terminal.jump_to_end_on_output = true;
        active_keybinding_map = "vscode";
        default_language = "bash";
        languages = {
          nix = {
            extensions = [ "nix" ];
            grammar = "nix";
            comment_prefix = "#";
            auto_indent = true;
            use_tabs = false;
            tab_size = 2;
            formatter = {
              command = "${pkgs.nixfmt-rfc-style}/bin/nixfmt";
              args = [
                "$FILE"
              ];
              stdin = false;
              timeout_ms = 10000;
            };
            format_on_save = true;
          };
          bash = {
            filenames = [
              ".bashrc"
              ".bash_profile"
              ".bash_aliases"
              ".bash_logout"
              ".profile"
              ".zshrc"
              ".zprofile"
              ".zshenv"
              ".zlogin"
              ".zlogout"
            ];
            extensions = [
              "sh"
              "bash"
              "zsh"
            ];
            grammar = "bash";
            comment_prefix = "#";
            formatter = {
              command = "${pkgs.shfmt}/bin/shfmt";
              args = [
                "-i"
                "2"
                "-w"
                "$FILE"
              ];
              stdin = false;
              timeout_ms = 10000;
            };
            format_on_save = true;
          };
          json.formatter = {
            command = "${pkgs.nodePackages.prettier}/bin/prettier";
            args = [
              "--write"
              "$FILE"
            ];
            stdin = false;
            timeout_ms = 10000;
          };
          yaml.formatter = {
            command = "${pkgs.nodePackages.prettier}/bin/prettier";
            args = [
              "--write"
              "$FILE"
            ];
            stdin = false;
            timeout_ms = 10000;
          };
          markdown = {
            line_wrap = true;
            page_view = true;
            page_width = 100;
            formatter = {
              command = "${pkgs.nodePackages.prettier}/bin/prettier";
              args = [
                "--write"
                "$FILE"
              ];
              stdin = false;
              timeout_ms = 10000;
            };
          };
        };
        lsp = {
          nix = [
            {
              name = "nil";
              command = "${pkgs.nil}/bin/nil";
              enabled = true;
              auto_start = true;
              root_markers = [
                "flake.nix"
                "default.nix"
                ".git"
              ];
            }
          ];
          bash = [
            {
              name = "bash-language-server";
              command = "${pkgs.bash-language-server}/bin/bash-language-server";
              args = [ "start" ];
              enabled = true;
              auto_start = true;
              root_markers = [
                ".git"
              ];
            }
          ];
          typescript = [
            {
              name = "typescript-language-server";
              command = "${pkgs.typescript-language-server}/bin/typescript-language-server";
              args = [ "--stdio" ];
              enabled = true;
              auto_start = true;
              root_markers = [
                "package.json"
                "tsconfig.json"
                ".git"
              ];
              language_id_overrides = {
                tsx = "typescriptreact";
                jsx = "javascriptreact";
              };
            }
          ];
          json = [
            {
              name = "vscode-json-language-server";
              command = "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server";
              args = [ "--stdio" ];
              enabled = true;
              auto_start = true;
              root_markers = [
                "package.json"
                ".git"
              ];
            }
          ];
          yaml = [
            {
              name = "yaml-language-server";
              command = "${pkgs.yaml-language-server}/bin/yaml-language-server";
              args = [ "--stdio" ];
              enabled = true;
              auto_start = true;
              root_markers = [
                ".git"
              ];
            }
          ];
        };
      };
    in
    {
      options.programs.fresh.enable = mkEnableOption "Fresh terminal editor defaults" // {
        default = true;
      };

      config = mkIf config.programs.fresh.enable {
        preferences.zsh.aliases.f = "fresh";

        system.activationScripts.fresh-user-config = {
          text = self.lib.userFiles.mkActivationScript {
            inherit user homeDirectory pkgs;
            files = {
              ".config/fresh/config.json" = {
                text = builtins.toJSON freshConfig;
                type = "copy";
                permissions = "0644";
              };
            };
          };
          deps = [ "users" ];
        };

        impermanence.home.cache.directories = [
          ".cache/fresh"
        ];
      };
    };

  perSystem =
    { pkgs, ... }:
    {
      packages.fresh = pkgs.unstable.fresh-editor;
    };
}
