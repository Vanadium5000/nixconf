This NixOS configuration flake provides a complete, modular system setup for running NixOS on a MacBook, focusing on reliability, security, productivity, and open-source principles. Key objectives include:

- **Modular Architecture**: Using flake-parts for organized, composable modules
- **Lightweight User Management**: Hjem as a home-manager alternative for user environments
- **Program Configuration**: Lassulus/wrappers for declarative program setup
- **Single-Command Deployment**: Entire system deployable via `nix run`
- **Ephemeral Systems**: Impermanence for clean, reliable reinstalls
- **Security**: Password-store integration with environment variables (transitioning to rebuild script)
- **Quick Installation**: Disko and Btrfs for automated partitioning and fast deploys
- **Desktop Environment**: Hyprland with DankMaterialShell for modern Wayland experience
- **Development Tools**: VSCodium, terminal tools, and BunJS scripting
- **Correctness**: Every detail verified for perfection and reliability

The setup prioritizes open-source software, security best practices, and productive workflows while maintaining room for continuous improvement.
