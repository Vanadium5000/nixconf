{
  lib,
  buildNpmPackage,
  fetchurl,
  python3,
  pkg-config,
  nodePackages,
}:

let
  version = "1.9.10";
in
buildNpmPackage (finalAttrs: {
  pname = "openchamber-web";
  version = version;

  # Use the published npm tarball because it matches the package metadata that
  # the vendored lockfile is generated from for offline Nix builds.
  # Ref: https://registry.npmjs.org/@openchamber/web/-/web-${version}.tgz
  src = fetchurl {
    url = "https://registry.npmjs.org/@openchamber/web/-/web-${version}.tgz";
    hash = "sha256-WEdzdNDoPsmzjBZc12ep169LDegqMSTMN5bnOfeZ+Yw=";
  };

  # Copy a pinned lockfile into the release tarball because upstream ships a
  # prebuilt npm artifact without package-lock.json, and buildNpmPackage needs
  # one stable dependency graph to reproduce the npm closure.
  # Ref: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/npm.section.md#vendoring-deps
  sourceRoot = "package";
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  # Native build inputs needed for node-pty native module compilation
  # Ref: https://github.com/microsoft/node-pty#installation
  nativeBuildInputs = [
    python3
    pkg-config
    nodePackages.node-gyp
  ];

  # Pin the npm dependency closure from the vendored lockfile so update-pkgs can
  # bump both the release tarball hash and this reproducible npm dependency hash.
  # Ref: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/npm.section.md#vendoring-deps
  npmDepsHash = "sha256-RQFaeCNP1Zqqu2v91098nZ1JmeEhq86hUoAmbBg34hs=";
  # The GitHub release tarball already includes built dist/ and server assets,
  # so rerunning the Vite build would only add unnecessary toolchain churn.
  dontNpmBuild = true;

  # Rebuild node-pty after installation to ensure it's built against system libraries
  # Ref: https://github.com/microsoft/node-pty#rebuilding
  postInstall = ''
    cd "$out/lib/node_modules/@openchamber/web"
    npm rebuild node-pty
  '';

  meta = {
    description = "Web interface for the OpenCode AI coding agent";
    homepage = "https://github.com/openchamber/openchamber";
    changelog = "https://github.com/openchamber/openchamber/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "openchamber";
    platforms = lib.platforms.linux;
  };
})
