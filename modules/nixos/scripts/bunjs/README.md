# Bun Scripts Workspace

Install dependencies from the repository root so workspaces and editor tooling
stay aligned on fresh clones:

```bash
bun install
```

You can still install directly in this workspace if needed:

```bash
bun install --cwd modules/nixos/scripts/bunjs
```

Useful commands:

```bash
bun run --cwd modules/nixos/scripts/bunjs build:web-ui
bunx tsc -p modules/nixos/scripts/bunjs/tsconfig.json --noEmit
```

This workspace packages the Bun/TypeScript utilities consumed by the flake and
keeps `node_modules` discoverable for LSPs on machines that only have a fresh
checkout plus a root-level package install.
