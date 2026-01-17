# AGENTS.md - NixOS Configuration Repository

This is a NixOS configuration flake using `flake-parts` and `import-tree` for modular system configuration. It relies on `path:.` for flake operations to include gitignored files (like `secrets.nix`).

## Repository Structure

```text
nixconf/
├── flake.nix           # Main flake definition
├── rebuild.sh          # System rebuild script (wraps nixos-rebuild)
├── secrets.nix         # Auto-generated secrets (gitignored, loaded by rebuild.sh)
├── modules/
│   ├── common/         # Shared base modules (impermanence, networking)
│   ├── hosts/          # Per-machine configs (legion5i, macbook, ionos_vps)
│   ├── nixos/          # NixOS-specific modules (desktop, terminal, scripts)
│   ├── programmes/     # Application configurations
│   ├── hjem/           # User environment (custom home-manager alternative)
│   ├── lib/            # Custom library functions (via self.lib)
│   ├── _pkgs/          # Custom package definitions (via self.packages)
│   └── theme.nix       # Theme definitions (via self.theme/self.colors)
```

## Build Commands

**Crucial:** Always use `path:.` when referring to the flake to ensure gitignored files (like `secrets.nix`) are included in the build source.

```bash
# Build and switch (most common)
HOST=legion5i ./rebuild.sh switch

# Build without switching (good for testing)
HOST=macbook ./rebuild.sh build

# Dry-run to preview changes
HOST=legion5i ./rebuild.sh dry-run

# Validate flake before switching (runs nix flake check)
HOST=legion5i ./rebuild.sh --validate switch

# Deploy to remote host
HOST=ionos_vps ./rebuild.sh deploy root@host

# Install on new machine (via nixos-anywhere)
HOST=macbook ./rebuild.sh install root@192.168.1.100

# Rollback
HOST=legion5i ./rebuild.sh rollback

# Show generations
HOST=legion5i ./rebuild.sh generations
```

## Linting and Formatting

We use `nixfmt-rfc-style` for formatting. **Do not use alejandra.**

```bash
# Format all Nix files (Required)
nixfmt .

# Format single file
nixfmt path/to/file.nix

# Linting
statix check .   # Check for issues
statix fix .     # Auto-fix issues
```

## Code Style & Conventions

### Commenting Policy

- **Concise & Useful:** Add comments *only* when the "why" isn't obvious from the code.
- **Avoid Redundancy:** Do not describe *what* the code does (e.g., `# Enable docker` above `virtualisation.docker.enable = true` is bad).
- **Context:** Explain complex logic, workarounds, or non-standard configurations.
- **Header:** Top-level modules should have a brief description of their purpose.

### Module Structure

Modules follow the `flake-parts` pattern. Use `import-tree` for directory structures.

```nix
{ self, inputs, ... }:
{
  flake.nixosModules.my-module = { pkgs, config, lib, ... }:
    let
      inherit (lib) mkOption mkIf types;
      cfg = config.preferences.my-module;
    in
    {
      options.preferences.my-module = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable my-module functionality";
        };
      };

      config = mkIf cfg.enable {
        # Config implementation
      };
    };
}
```

### Preferences System (`config.preferences`)

The configuration is controlled via a centralized `preferences` option tree (defined in `modules/common/base.nix`).

- `preferences.enable`: Global enable flag (default true).
- `preferences.hostName`: Machine hostname.
- `preferences.user.username`: Main user's username.
- `preferences.user.extraGroups`: Additional groups for the user.
- `preferences.system.backlightDevice`: Hardware ID for backlight.
- `preferences.allowedUnfree`: List of allowed unfree packages.
- `preferences.autostart`: List of packages/commands to autostart.

**Usage:**
Use `config.preferences.user.username` instead of hardcoding "matrix".

### Custom Packages (`_pkgs`)

Packages in `modules/_pkgs/` are automatically exposed via `self.packages`.

- File name must match the package name (e.g., `daisyui-mcp.nix`).
- Do not create a `default.nix` in `_pkgs/`.

```nix
# modules/_pkgs/my-tool.nix
{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  pname = "my-tool";
  version = "1.0";
  # ...
}
```

### Custom Library (`modules/lib`)

Accessible via `self.lib`. Contains helpers for persistence and config generation.

```nix
# Import lib functions
inherit (self.lib.persistence) mkPersistent;
inherit (self.lib.generators) toHyprconf;

# Usage
file = mkPersistent {
  user = config.preferences.user.username;
  fileName = "settings.json";
  targetFile = "/home/user/.config/app/settings.json";
};
```

### Formatting Rules

- **Formatter:** `nixfmt` (RFC style).
- **Indentation:** 2 spaces.
- **Lists:** Single-item lists on one line, multi-item lists = one per line.
- **Imports:** Grouped at the top of the `let` block or `imports` list.

## Impermanence & Persistence

This system uses ephemeral root storage. You **MUST** explicitly persist files/directories that should survive a reboot.

### Critical Data (Backed up)

Use `impermanence.nixos` (system) or `impermanence.home` (user).

**Guidelines:**

- Add directories containing configuration, database files, or keys.
- Add specific files if the parent directory shouldn't be persisted.

```nix
# System Persistence
impermanence.nixos.directories = [
  "/var/lib/nixos"
  "/var/lib/bluetooth"
];
impermanence.nixos.files = [
  "/etc/machine-id"
];

# User Persistence
impermanence.home.directories = [
  "Documents"
  "nixconf"
  ".ssh"
  ".config/obsidian"
];
impermanence.home.files = [
  ".zsh_history"
];
```

### Cache / Large Data (Not Backed Up)

Use `impermanence.*.cache` for large files or download artifacts (>50MB) that can be re-downloaded or regenerated. Cache directories are persisted across reboots just like regular persistence, but are **not included in backups**. They are never automatically cleaned up - the only difference is backup inclusion.

```nix
# System Cache
impermanence.nixos.cache.directories = [
  "/var/cache/ollama" # Large AI models
];

# User Cache
impermanence.home.cache.directories = [
  ".cache/mozilla"
  ".cache/spotify"
  "Downloads"       # Large downloads
  ".local/share/Steam" # Game files
];
```

## Flake & Advanced Patterns

### Self-References

Access flake outputs directly via `self`:

- `self.nixosModules.*`: Access other modules.
- `self.packages.${pkgs.system}.*`: Access custom packages.
- `self.theme`: Access the global theme definition.
- `self.colors`: Access the generated color palette.
- `self.secrets`: Access runtime secrets (loaded via `rebuild.sh`).

### Secrets Management

Secrets are managed via `pass` (password-store) and `secrets.nix`.

1. `rebuild.sh` reads secrets from `pass` based on `SECRETS_MAP`.
2. It generates `secrets.nix` (ignored by git).
3. `flake.nix` imports `secrets.nix` and exposes `self.secrets`.
4. Modules access secrets via `self.secrets.SECRET_NAME`.

**Note:** Never commit actual secrets. `secrets.nix` is in `.gitignore`.

### Input Handling

- Use `inputs.nixpkgs.lib` for standard library functions.
- Use `inputs.<flake>.nixosModules.<module>` for external modules.
- Use `self` for internal references.

## Common Tasks

**Adding a new Host:**

1. Create `modules/hosts/<hostname>/default.nix`.
2. Define `flake.nixosConfigurations.<hostname>`.
3. Import `self.nixosModules.desktop` (or terminal/common).
4. Set `preferences.hostName` and hardware config.

**Adding a Package:**

1. If available in nixpkgs: add to `environment.systemPackages`.
2. If custom: add `modules/_pkgs/<name>.nix`, then add to system packages using `self.packages.${pkgs.system}.<name>`.

**Debugging Build Failures:**

1. Check `nix log` for detailed error messages.
2. Verify `path:.` is used (default in `rebuild.sh`) so dirty/ignored files are seen.
3. Check `impermanence` paths if state is lost on reboot.
