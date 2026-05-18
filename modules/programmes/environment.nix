{ self, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    let

      edgePkgs = pkgs.unstable;
      userPackageEnv = self.lib.userPackages.environment;

      rawPackages = [
        # Wrapped programmes
        self'.packages.qalc
        self'.packages.monero-wallet
        self'.packages.bitcoin-wallet
        self'.packages.ethereum-wallet
        self'.packages.git
        self'.packages.starship
        self'.packages.fresh
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
            nix-prefetch-github
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

            # Required for ESP32 USB access
            platformio-core.udev
            openocd

            psmisc # Set of small useful utilities that use the proc filesystem (such as fuser, killall and pstree)
            rclone

            tealdeer # Very fast implementation of tldr in Rust
            btop # System resource monitor
            bat
            zip
            unzip
            _7zz
            jq

            (pass.withExtensions (exts: [ exts.pass-otp ])) # Password management

            fastfetch # Device info
            cpufetch # CPU info
            nix-tree # Nix storage info
            speedtest-go # Internet speed test using speedtest.net
            iperf3 # Connection benchmarking

            # Network monitoring TUI tools
            termshark # TUI packet analyzer (uses tshark backend)
            usbutils # Tools for working with USB devices, such as lsusb
            iw # Configuration utility for wireless devices

            # BTRFS
            btdu # Disk usage
          ]
          ++ [
            self'.packages.snitch # TUI for inspecting network connections (netstat for humans)
          ]
          ++
            # Language runtimes/compilers
            [
              python3
              gcc
              #edgePkgs.bun # Replaced by "curl -fsSL https://bun.sh/install | bash"
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
              edgePkgs.yt-dlp
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
              edgePkgs.aircrack-ng # WiFi security auditing suite - unstable has better support for newer drivers
              nmap # Network discovery and security auditing
              metasploit # Penetration testing framework
              thc-hydra # Network logon cracker (supports SSH, FTP, etc.)
              john # "John the Ripper" password cracker
              sqlmap # Automated SQL injection tool
              gobuster # URI/DNS brute-forcing tool
              ffuf # Fast web fuzzer
              hashcat # Advanced password recovery
              hcxtools # hcxpcapngtool, hcxdumptool

              # Network / MITM
              bettercap # Network attacks and monitoring
              responder # LLMNR/NBT-NS/mDNS poisoner

              # Web Security
              zap # OWASP ZAP security scanner
              xxd # Hex dump tool
              linux-wifi-hotspot # WiFi hotspot tool
              hostapd # WiFi access point software
              wirelesstools # Tools for working with wireless devices
              dnsmasq # DNS forwarder and DHCP server
              ipset # IP set utility

              # Reverse Engineering
              ghidra # Software reverse engineering suite
              radare2 # Unix-like reverse engineering framework
              binwalk # Firmware analysis tool

              # Utilities
              rustscan # Fast port scanner
              socat # Multipurpose relay (SOcket CAT)
              proxychains-ng # Force connections through proxy servers
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
        env = userPackageEnv // {
          EDITOR = "${self'.packages.fresh}/bin/fresh";
          VISUAL = "${self'.packages.fresh}/bin/fresh";
          PASSWORD_STORE_DIR = "$HOME/.local/share/password-store";
        };
      };

      packages.rebuild = pkgs.writeShellScriptBin "rebuild" ''
        exec ${../../rebuild.sh} "$@"
      '';
    };
}
