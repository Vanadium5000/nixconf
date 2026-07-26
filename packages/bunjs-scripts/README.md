# Bun Scripts Workspace

Install dependencies from the repository root so workspaces and editor tooling
stay aligned on fresh clones:

```bash
bun install
```

You can still install directly in this workspace if needed:

```bash
bun install --cwd packages/bunjs-scripts
```

Useful commands:

```bash
bun run --cwd packages/bunjs-scripts build:web-ui
bunx tsc -p packages/bunjs-scripts/tsconfig.json --noEmit
```

The packaged Nix outputs do not read `node_modules` from your checkout.
Dependency-bearing scripts are bundled or built from the committed lockfiles in
the sandbox, while a local `bun install` remains useful for editor tooling and
interactive development on fresh clones.
