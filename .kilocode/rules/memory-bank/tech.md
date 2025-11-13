# Technologies Used

## Core Technologies

- **NixOS**: Declarative Linux distribution with atomic updates
- **Flake-parts**: Framework for modular Nix flake composition
- **Import-tree**: Automatic directory-to-module conversion
- **Hjem**: Lightweight home-manager alternative for user environments
- **Lassulus/wrappers**: Declarative program configuration wrapper

## Desktop Environment

- **Hyprland**: Modern Wayland compositor with tiling window management
- **DankMaterialShell**: Material Design-inspired shell interface
- **Wayland**: Next-generation display protocol
- **PipeWire**: Audio and video server

## Development Tools

- **VSCodium**: Open-source VS Code fork
- **Fish Shell**: User-friendly shell with syntax highlighting
- **Starship**: Cross-shell prompt with Git integration
- **Kitty**: GPU-accelerated terminal emulator
- **BunJS**: Fast JavaScript runtime and bundler

## System Management

- **Impermanence**: Ephemeral system with selective persistence
- **Disko**: Declarative disk partitioning
- **Btrfs**: Modern filesystem with subvolumes and snapshots
- **NetworkManager**: Network configuration management

## Security & Privacy

- **Password-store**: Secure credential management
- **SSH**: Secure remote access with key-only authentication
- **Firewall**: Network filtering and protection
- **DNS over TLS**: Encrypted DNS resolution

## Hardware Support

- **NixOS Hardware**: Apple MacBook T2 chip support
- **Broadcom Wi-Fi**: Firmware for Apple T2 Wi-Fi
- **Intel Graphics**: Hardware acceleration support

## Development Setup

- **Nix Flakes**: Reproducible package management
- **Direnv**: Automatic environment activation
- **Git**: Version control with Nix integration
- **Nix-index**: Fast package searching

## Technical Constraints

- **MacBook Hardware**: Limited to Apple T2 chip compatibility
- **Wayland Only**: No X11 fallback for modern desktop experience
- **Ephemeral Design**: System must be reinstallable without data loss
- **Open Source Only**: All components must be free and open source

## Tool Usage Patterns

- **Single Command Deployment**: `nix run` for complete system setup
- **Flake Check**: `nix flake check` for configuration validation
- **Atomic Updates**: `nixos-rebuild switch` for system updates
- **Impermanence**: Selective persistence for critical data only
