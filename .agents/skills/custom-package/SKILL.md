---
name: custom-package
description: Package custom software for this NixOS flake under packages/ or external-packages/, wire update-pkgs support, validate builds/runtime, and decide terminal host exclusions.
allowed-tools: Read, Find, Search, Bash, Edit, Write
---

# Custom Package Packaging

Use this skill when adding or maintaining a custom package in this flake.

## Non-negotiables

- In-repo software lives in `packages/<pname>/package.nix`; packaged upstream projects live in `external-packages/<pname>/package.nix`. Package-owned modules/assets live beside that package. Use `programmes/<name>/` for wrappers/configuration around upstream tools instead of creating a package.
- Do not run `./rebuild.sh`, `nixos-rebuild`, or other system rebuild commands.
- Evaluate with `path:.#...`, not `.#...`, so untracked package files are included.
- Link upstream and packaging sources in package comments when the detail is non-obvious, and in the final response. Prefer `# Source:` or `# Ref:` near the setting it justifies.
- Do not ship a package until it builds and its main executable runs `--help`, `-h`, `--version`, or another safe smoke command.
- Add/update `external-packages/update-pkgs/workflow.nix` support before finishing external package changes: update strategy, test command, and any package-set membership if relevant.
- If an external package has no safe automatic updater, mark it `manual` with a reason in `workflow.nix`; uncovered package directories warn in `checks.update-pkgs-workflow-coverage` and when `update-pkgs` runs.
- Inspect `modules/terminal/default.nix`, desktop modules, and host modules before installing a new package. Packages are opt-in through the narrowest profile/feature/host that needs them; do not add aggregate package sets to `common`.

## Workflow

1. Identify upstream:
   - Release/tag source, lockfiles, build system, license, main binary, runtime assets, and platform support.
   - Prefer tagged releases over branch commits unless upstream has no releases.
2. Choose package helper:
   - Plain C/C++/misc: `stdenv.mkDerivation`.
   - Rust: `rustPlatform.buildRustPackage`; prefer `cargoLock = { lockFile = "${src}/Cargo.lock"; }` when upstream has a complete lockfile. Use `cargoHash` only when lock import is impossible or intentionally better.
   - Go: `buildGoModule` with `vendorHash`.
   - npm/Node: `buildNpmPackage` with a checked-in or upstream `package-lock.json` and `npmDepsHash`.
   - Bun: prefer nixpkgs Bun hooks/build helpers when available; otherwise use a fixed-output dependency/build derivation with `bun install --frozen-lockfile --offline` semantics. Do not allow network during build.
   - Binary/AppImage/RPM/deb: use fixed-output fetchers, `autoPatchelfHook`/wrappers as needed, and set `sourceProvenance`.
3. Write `packages/<pname>/package.nix` or `external-packages/<pname>/package.nix`:
   - Keep arguments explicit and sorted enough to scan.
   - Include `meta.description`, `homepage`, `license`, `mainProgram`, `platforms`, and `sourceProvenance` for binaries.
   - Explain patches, vendoring choices, network disabling, and runtime wrappers with linked sources.
4. Wire exports:
   - Package directories with `package.nix` are auto-exported by `packages/_exports/default.nix`.
   - If the package needs unstable toolchains/dependencies, add it to `edgePackages` with a source-linked rationale.
5. Wire updates:
   - Add the package to the appropriate set in `external-packages/update-pkgs/workflow.nix` or document why it is manual.
   - Treat a missing workflow entry as a bug unless the package is intentionally out of scope and has a `manualReasons` entry.
   - Add custom update logic when version, source hash, dependency hash, and generated assets must move together.
   - Ensure `update-pkgs test <pname>` builds the flake package and runs a safe smoke command.
6. Profile placement:
   - Read `modules/terminal/default.nix` and the relevant desktop/host module.
   - Install the package only in the narrowest profile, feature, service, or host that needs it. GUI, heavy, platform-specific, unfree, Android/iOS, browser, and daemon packages should not enter broad common profiles.
7. Validation:
   - `nix build path:.#<pname>`
   - `result/bin/<mainProgram> --help` or the nearest safe equivalent.
   - `update-pkgs test <pname>` after wiring update-pkgs.
   - `nix eval path:.#packages.x86_64-linux.<pname>.meta.mainProgram` when checking metadata only.

## Reliable Rust packaging

Prefer `cargoLock` when possible because nixpkgs imports the lockfile into fixed-output crate derivations and avoids the version-sensitive vendor tarball churn of `cargoHash`.

```nix
rustPlatform.buildRustPackage {
  pname = "example";
  version = "1.2.3";
  src = fetchFromGitHub { /* ... */ };

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    # Required for git dependencies; build once with lib.fakeHash to discover.
    outputHashes = {
      # "crate-name-0.1.0" = "sha256-...";
    };
  };
}
```

Use `cargoHash = lib.fakeHash` only to discover a missing hash. If upstream lockfiles are patched or generated, use `cargoLock.lockFileContents` and copy the resulting lockfile into `src` in `postPatch`.

## Source links

Use these before guessing APIs:

- Nixpkgs quick package guide: https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md
- Standard environment and phases: https://nixos.org/manual/nixpkgs/stable/#chap-stdenv
- Rust packaging: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/rust.section.md
- `buildRustPackage` implementation: https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/rust/build-rust-package/default.nix
- npm packaging: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/javascript.section.md
- Go packaging: https://nixos.org/manual/nixpkgs/stable/#ssec-language-go
- Bun cache/install model: https://bun.sh/docs/install/cache
- bun2nix packaging docs when used: https://github.com/baileyluTCD/bun2nix/tree/main/docs/src/building-packages
