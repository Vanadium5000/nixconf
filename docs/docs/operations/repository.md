---
title: Repository map
---

This flake is an operational NixOS fleet configuration, not a reusable framework.

```text
flake.nix
  -> modules/
  -> modules/hosts/*
  -> modules/nixos/*
  -> docs/
```

## Important local paths

- `AGENTS.md`: mandatory AI agent operating instructions at the repository root.
- `modules/hosts/`: active host definitions.
- `modules/nixos/terminal/`: terminal/server profile modules.
- `modules/nixos/desktop/`: graphical profile modules.
- `modules/nixos/terminal/monitoring/homepage.nix`: Homepage dashboard cards and bookmarks.

## Change rule

When a change affects operator behavior, public routes, host services, or recovery steps, update `docs/` in the same patch.

## Docs development dependencies

Run dependency installs from the repository root so Bun wires every local workspace, including this Docusaurus site and the Bun script workspace:

```bash
bun install
```

The root `package.json` includes `docs/` in `workspaces`, so that single command installs the Docusaurus packages needed by `docs/docusaurus.config.ts`, `docs/sidebars.ts`, and editor TypeScript language services. Keep `docs/package-lock.json` committed as well: the NixOS docs module at `modules/nixos/terminal/docs.nix` uses it for reproducible `pkgs.buildNpmPackage` builds during rebuilds.

```nix
# Typical module shape in this repository.
{ self, ... }:
{
  flake.nixosModules.example = { config, lib, ... }: {
    options.services.example.enable = lib.mkEnableOption "example service";
    config = lib.mkIf config.services.example.enable {
      # service config
    };
  };
}
```

## References

- [NixOS module system](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
- [flake-parts](https://flake.parts/)
- [import-tree](https://github.com/vic/import-tree)
