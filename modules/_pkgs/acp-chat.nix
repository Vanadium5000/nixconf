{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  makeWrapper,
  pkg-config,
  libsecret,
}:

buildNpmPackage {
  pname = "acp-chat";
  version = "0.1.37-unstable-2026-03-29";

  src = fetchFromGitHub {
    owner = "strato-space";
    repo = "acp-plugin";
    rev = "6cf76808771a76f636e7df8dafe3f52a2d992060";
    hash = "sha256-F+JpNM39TWhFHtIVQx80MS0IwEP5Vb2+vXczxg2+0Yw=";
  };

  sourceRoot = "source/acp-chat";

  npmDepsHash = "sha256-gxlUu1kSwuBCK1xUAsyV562wupgCOekJNwYJVm2Oy70=";
  npmDepsFetcherVersion = 2;

  postPatch = ''
        # Upstream acp-chat/package-lock.json lists esbuild@0.27.3 but omits the
        # matching linux-x64 optional package, so esbuild tries a network install
        # during npmConfigHook. Add the exact npm registry metadata so Nix's fixed
        # dependency cache stays offline and reproducible.
        # Source: package-lock.json esbuild optionalDependencies and npm metadata for
        # https://registry.npmjs.org/@esbuild/linux-x64/0.27.3.
    substituteInPlace package-lock.json \
      --replace-fail '    "node_modules/escalade": {' '    "node_modules/@esbuild/linux-x64": {
      "version": "0.27.3",
      "resolved": "https://registry.npmjs.org/@esbuild/linux-x64/-/linux-x64-0.27.3.tgz",
      "integrity": "sha512-Czi8yzXUWIQYAtL/2y6vogER8pvcsOsk5cpwL4Gk5nJqH5UZiVByIY8Eorm5R13gq+DQKYg0+JyQoytLQas4dA==",
      "cpu": [
        "x64"
      ],
      "license": "MIT",
      "optional": true,
      "os": [
        "linux"
      ],
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/escalade": {'

    # npm runs file: workspace prepare scripts during `npm ci`; acp-ui lives
    # outside sourceRoot, so give that script the already-vendored toolchain.
    # Source: packages/acp-ui/package.json prepare/build and npmConfigHook log.
    chmod +w ../packages/acp-ui
    ln -s "$PWD/node_modules" ../packages/acp-ui/node_modules
  '';

  # esbuild ships its platform binary as an optional npm dependency; include
  # optional deps so npm can install @esbuild/linux-x64 from the fixed cache.
  # Source: node_modules/esbuild/install.js error text during the Nix build.
  npmInstallFlags = [ "--include=optional" ];

  # npmConfigHook already installs from the fixed cache with --ignore-scripts;
  # keep rebuild from running transitive prepare scripts such as style-to-object's
  # husky hook, while esbuild is satisfied by the optional binary package above.
  # Source: npmConfigHook and Nix build log for node_modules/style-to-object.
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [ libsecret ];

  buildPhase = ''
    runHook preBuild

    # Build from acp-chat's own lockfile/workspaces because the root package
    # does not include acp-chat/server; upstream documents `cd acp-chat && npm
    # ci && npm run build`. Source: acp-chat/README.md and acp-chat/package.json.
    # The build:web script enters ../packages/acp-ui, so expose acp-chat's fixed
    # node_modules binaries there instead of letting npm look for sibling-local
    # installs. Source: acp-chat/package.json build:ui and the Nix build log.
    export PATH="$PWD/node_modules/.bin:$PATH"
    npm run build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app_root="$out/lib/acp-chat-source"
    app_dir="$app_root/acp-chat"
    mkdir -p "$app_dir" "$app_root/packages" "$out/bin"

    cp -a package.json package-lock.json node_modules server web "$app_dir/"
    rm -f ../packages/acp-ui/node_modules
    cp -a ../package.json ../package-lock.json "$app_root/"
    cp -a ../packages/acp-runtime-shared ../packages/acp-ui "$app_root/packages/"

    makeWrapper ${nodejs}/bin/node "$out/bin/acp-chat" \
      --chdir "$app_dir" \
      --set NODE_PATH "$app_dir/node_modules" \
      --add-flags "$app_dir/server/dist/index.js"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -f "$out/lib/acp-chat-source/acp-chat/server/dist/index.js"
    test -f "$out/lib/acp-chat-source/acp-chat/web/dist/index.html"
    test -x "$out/bin/acp-chat"

    runHook postInstallCheck
  '';

  meta = {
    description = "Browser chat UI for Agent Client Protocol agents";
    homepage = "https://github.com/strato-space/acp-plugin/tree/main/acp-chat";
    license = lib.licenses.asl20;
    mainProgram = "acp-chat";
    platforms = lib.platforms.linux;
  };
}
