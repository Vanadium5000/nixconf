# System Architecture

## Source Code Paths

### Core Flake Structure

- `flake.nix` - Main flake definition with inputs and outputs using flake-parts
- `modules/flake-parts.nix` - Supported systems configuration

### Modular Architecture (flake-parts)

- `modules/common/` - Shared configurations across all systems
  - `base.nix` - User management, SSH, locales, boot settings
  - `impermanence.nix` - Ephemeral system configuration with persistence
  - `keymap.nix` - Hyprland keybinding definitions
  - `networking.nix` - NetworkManager, DNS, firewall settings

### Host-Specific Configurations

- `modules/hosts/macbook/` - MacBook-specific setup
  - `configuration.nix` - Main host configuration with hardware modules
  - `disko.nix` - Automated disk partitioning (EFI + Btrfs subvolumes)
  - `hardware-configuration.nix` - Hardware detection and kernel modules

### NixOS Modules

- `modules/nixos/` - System-level configurations
  - `terminal/` - Terminal environment setup
    - `default.nix` - Common terminal modules (dev, nix)
    - `dev.nix` - Development tools (MongoDB, Ollama)
    - `nix.nix` - Nix package manager configuration
  - `desktop/` - Desktop environment components
    - `default.nix` - Desktop module aggregation
    - `hyprland.nix` - Hyprland compositor configuration
    - `vscodium/` - VSCodium IDE setup with extensions
    - `dankmaterialshell.nix` - DankMaterialShell configuration
    - `system/` - System services (audio, bluetooth)
    - `flatpaks/` - Flatpak application management

### User Environment (hjem)

- `modules/hjem/` - User-level configurations
  - `hjem.nix` - Hjem module setup
  - `hyprland.nix` - Hyprland user configuration with keybindings
  - `dankmaterialshell/` - DankMaterialShell user module

### Program Configurations

- `modules/programmes/` - Program-specific wrappers and configurations
  - `environment.nix` - Main environment wrapper with CLI tools
  - `fish.nix` - Fish shell configuration with Starship
  - `starship.nix` - Starship prompt configuration
  - `kitty.nix` - Kitty terminal emulator setup
  - `waybar/` - Waybar status bar modules
  - `wrappers/` - Lassulus/wrappers configurations

### Supporting Files

- `modules/secrets.nix` - Environment variable secret management
- `modules/theme.nix` - Color scheme and theme definitions

## Key Technical Decisions

### Modular Architecture

- **flake-parts**: Enables composable, modular flake structure
- **Import-tree**: Automatic directory-to-module conversion
- **Separation of Concerns**: Clear boundaries between system, user, and program configurations

### User Management

- **hjem**: Lightweight alternative to home-manager for user environments
- **Impermanence**: Ephemeral systems with selective persistence
- **Password-store**: Secure credential management

### Desktop Environment

- **Hyprland**: Modern Wayland compositor with extensive customization
- **DankMaterialShell**: Material Design-inspired shell interface
- **Wayland-native**: Full Wayland stack for better performance and security

### Development Environment

- **VSCodium**: Open-source VS Code fork with curated extensions
- **Multi-language Support**: Nix, Rust, Python, Go, web development tools
- **Terminal Tools**: Fish shell, Starship prompt, Kitty terminal

## Component Relationships

### System Layer

```
flake.nix
├── flake-parts (modular structure)
├── import-tree (auto-module loading)
└── modules/
    ├── common/ (shared configs)
    ├── hosts/macbook/ (hardware-specific)
    └── nixos/ (system services)
```

### User Layer

```
hjem
├── hyprland (window manager)
├── dankmaterialshell (interface)
└── program configs (editors, terminals)
```

### Program Layer

```
wrappers (Lassulus/wrappers)
├── environment (main CLI tools)
├── kitty (terminal)
├── starship (prompt)
└── fish (shell)
```

## Critical Implementation Paths

### Boot Process

1. Disko partitioning creates Btrfs subvolumes
2. Impermanence mounts persistent directories
3. System activates with user configuration
4. Hyprland starts with DankMaterialShell

### Development Workflow

1. VSCodium loads with configured extensions
2. Terminal (Kitty) provides Fish shell with Starship
3. Nix tools available for package management
4. Git and development tools ready

### Security Implementation

1. SSH hardened with key-only authentication
2. Firewall enabled with NetworkManager
3. Password-store for credential management
4. Impermanence prevents persistent malware
