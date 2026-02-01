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

      rawPackages = [
        # Wrapped programmes
        self'.packages.qalc
        self'.packages.monero-wallet
        self'.packages.bitcoin-wallet
        self'.packages.ethereum-wallet
        self'.packages.git
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
            wget
            curl

            sshfs # SSH filesystem tool

            hey # HTTP benchmarking tool

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
            speedtest-go # Internet speed test using speedtest.net

            # Network monitoring TUI tools
            termshark # TUI packet analyzer (uses tshark backend)
            usbutils # Tools for working with USB devices, such as lsusb
            iw # Configuration utility for wireless devices
          ]
          ++ [
            self'.packages.snitch # TUI for inspecting network connections (netstat for humans)
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
              lua # Lua
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
            # Security / Pentesting
            [
              aircrack-ng # WiFi security auditing suite
              nmap # Network discovery and security auditing
              metasploit # Penetration testing framework
              thc-hydra # Network logon cracker (supports SSH, FTP, etc.)
              john # "John the Ripper" password cracker
              sqlmap # Automated SQL injection tool
              gobuster # URI/DNS brute-forcing tool
              ffuf # Fast web fuzzer
              hashcat # Advanced password recovery
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
        package = self'.packages.zsh;
        runtimeInputs = rawPackages;
        env = {
          EDITOR = getExe editor;
          PASSWORD_STORE_DIR = "$HOME/.local/share/password-store";
        };
      };
    };
}
