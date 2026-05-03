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

The packaged Nix outputs do not read `node_modules` from your checkout.
Dependency-bearing scripts are bundled or built from the committed lockfiles in
the sandbox, while a local `bun install` remains useful for editor tooling and
interactive development on fresh clones.
