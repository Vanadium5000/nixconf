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

      # # Unstable pkgs
      # unstable = import inputs.nixpkgs-unstable {
      #   system = pkgs.stdenv.hostPlatform.system;
      # };

      editor = inputs.nvf-neovim.packages.${pkgs.stdenv.hostPlatform.system}.default;

      rawPackages = [
        # Wrapped programmes
        self'.packages.qalc
        self'.packages.monero-wallet
        self'.packages.starship
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

            sshfs # SSH filesystem tool

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

            (pass.withExtensions (exts: [ exts.pass-otp ])) # Password management

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
              nodejs_latest
              go
              sqlite
              sqlite-web # sqlite web editor
            ]
          ++
            # Media tools
            [
              imagemagick
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
          ++
            # Cryptocurrency tools
            [
              monero-cli
            ]
        )
      );
    in
    {
      # Expose the raw list (arbitrary attrset, so list is fine here)
      # legacyPackages is designed for non-buildable outputs (like lists or functions) that might be used in other flakes or shells
      legacyPackages.environmentPackages = rawPackages;

      packages.environment = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = self'.packages.fish;
        runtimeInputs = rawPackages;
        env = {
          EDITOR = getExe editor;
          PASSWORD_STORE_DIR = "$HOME/.local/share/password-store";
        };
      };
    };
}
