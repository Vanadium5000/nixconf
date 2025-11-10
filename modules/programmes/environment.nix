{
  lib,
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    let
      inherit (lib)
        getExe
        ;

      editor = inputs.nvf-neovim.packages.${pkgs.stdenv.hostPlatform.system}.default;
    in
    {
      packages.environment = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = self'.packages.fish;
        runtimeInputs = [
          # Wrapped programmes
          self'.packages.qalc
          editor
        ]
        ++ (
          with pkgs;
          (
            # Nix tooling
            [
              nil
              nixd
              statix
              nixfmt-rfc-style # Nix formatter
              manix
              nix-inspect
            ]
            # General CLI tools
            ++ [
              git
              wget
              curl

              fzf
              fd
              ripgrep

              tealdeer # Very fast implementation of tldr in Rust
              btop # System resource monitor
              bat
              zip
              unzip
              jq
              neovim

              pass # Password management

              fastfetch # Device info
              cpufetch # CPU info
              nix-tree # Nix storage info
            ]
            ++
              # Language runtimes/compilers
              [
                python3
                gcc
                bun
                go
                sqlite
                sqlite-web # sqlite web editor
              ]
            ++
              # Media tools
              [
                imagemagick
                imv
                ffmpeg
                yt-dlp
              ]
            ++
              # Just cool
              [
                pipes
                cmatrix
                cava
              ]
          )
        );
        env = {
          EDITOR = getExe editor;
          PASSWORD_STORE_DIR = ".local/share/password-store";
        };
      };
    };
}
