{
  lib,
  stdenv,
  fetchFromGitHub,
  bun,
  nodejs,
  python3,
  pkg-config,
  cargo,
  rustc,
  node-gyp,
}:

let
  version = "1.11.7";

  src = fetchFromGitHub {
    owner = "openchamber";
    repo = "openchamber";
    tag = "v${version}";
    hash = "sha256-yEgZXDjN9BjUDh5grpsXbyI4Ttjqtoc5DjxG84UFD8g=";
  };

  commonNativeBuildInputs = [
    bun
    nodejs
    python3
    pkg-config
    cargo
    rustc
    node-gyp
  ];

  bunEnv = ''
    export HOME="$TMPDIR"
    export BUN_INSTALL_CACHE_DIR="$TMPDIR/bun-cache"
    export npm_config_nodedir=${nodejs}
    export npm_config_build_from_source=true

    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    export ELECTRON_SKIP_BINARY_DOWNLOAD=1
    export PUPPETEER_SKIP_DOWNLOAD=1
    export CYPRESS_INSTALL_BINARY=0
  '';

  bunDeps = stdenv.mkDerivation {
    pname = "openchamber-web-bun-deps";
    inherit version src;

    nativeBuildInputs = commonNativeBuildInputs;

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-vmS2XeLvPk82g0d+v14zyPsfmhXiyrJqucyZxkJbrGM=";

    dontBuild = true;
    dontFixup = true;

    configurePhase = ''
      runHook preConfigure
      ${bunEnv}
      runHook postConfigure
    '';

    installPhase = ''
      runHook preInstall

      bun install \
        --frozen-lockfile \
        --ignore-scripts \
        --backend=copyfile \
        --filter './' \
        --filter '@openchamber/web' \
        --filter '@openchamber/ui'

      mkdir -p "$out"
      cp -a node_modules "$out/node_modules"

      if [ -d packages/web/node_modules ]; then
        mkdir -p "$out/packages/web"
        cp -a packages/web/node_modules "$out/packages/web/node_modules"
      fi

      if [ -d packages/ui/node_modules ]; then
        mkdir -p "$out/packages/ui"
        cp -a packages/ui/node_modules "$out/packages/ui/node_modules"
      fi

      runHook postInstall
    '';
  };
in
stdenv.mkDerivation {
  pname = "openchamber-web";
  inherit version src;

  nativeBuildInputs = commonNativeBuildInputs;

  configurePhase = ''
    runHook preConfigure
    ${bunEnv}

    cp -a ${bunDeps}/node_modules ./node_modules
    chmod -R u+w ./node_modules

    if [ -d ${bunDeps}/packages/web/node_modules ]; then
      mkdir -p packages/web
      cp -a ${bunDeps}/packages/web/node_modules packages/web/node_modules
      chmod -R u+w packages/web/node_modules
    fi

    if [ -d ${bunDeps}/packages/ui/node_modules ]; then
      mkdir -p packages/ui
      cp -a ${bunDeps}/packages/ui/node_modules packages/ui/node_modules
      chmod -R u+w packages/ui/node_modules
    fi

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    patchShebangs node_modules packages/web/node_modules packages/ui/node_modules
    bun run build:web

    npm rebuild better-sqlite3 --build-from-source --nodedir=${nodejs}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app_dir="$out/lib/openchamber"
    mkdir -p "$app_dir" "$out/bin"

    cp -a package.json bun.lock node_modules packages "$app_dir/"

    patchShebangs "$app_dir/packages/web/bin"
    chmod +x "$app_dir/packages/web/bin/cli.js"
    ln -s "$app_dir/packages/web/bin/cli.js" "$out/bin/openchamber"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -f "$out/lib/openchamber/packages/web/dist/index.html"
    test -d "$out/lib/openchamber/packages/web/dist/assets"
    "$out/bin/openchamber" --version | grep -F "${version}"

    runHook postInstallCheck
  '';

  meta = {
    description = "Web interface for the OpenCode AI coding agent";
    homepage = "https://github.com/openchamber/openchamber";
    changelog = "https://github.com/openchamber/openchamber/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "openchamber";
    platforms = lib.platforms.linux;
  };
}
