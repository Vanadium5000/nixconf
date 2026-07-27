{
  buildNpmPackage,
  bun,
  coreutils,
  importNpmLock,
  lib,
  nodejs,
  playwright,
  playwright-driver,
  writeShellApplication,
}:
let
  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      !(builtins.elem (baseNameOf path) [
        "node_modules"
        ".bun"
      ]);
  };
  bundle = buildNpmPackage {
    pname = "bunjs-playwright-stealth-browser-bundle";
    version = "0-unstable";
    inherit src;
    npmDeps = importNpmLock { npmRoot = src; };
    npmConfigHook = importNpmLock.npmConfigHook;
    nativeBuildInputs = [ bun ];
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      bun build --target=bun --outfile=playwright-stealth-browser.js playwright-stealth-browser.ts
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm444 playwright-stealth-browser.js "$out/share/bunjs-playwright-stealth-browser/playwright-stealth-browser.js"
      runHook postInstall
    '';
  };
  chromiumDir = builtins.head (
    builtins.filter (entry: builtins.match "chromium-.*" entry != null) (
      builtins.attrNames (builtins.readDir playwright-driver.browsers)
    )
  );
  chromiumBin = "${playwright-driver.browsers}/${chromiumDir}/chrome-linux/chrome";
in
writeShellApplication {
  name = "playwright-stealth-browser";
  runtimeInputs = [
    bun
    coreutils
    nodejs
    playwright
    playwright-driver.browsers
  ];
  text = ''
    export PLAYWRIGHT_BROWSERS_PATH=${playwright-driver.browsers}
    export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=${chromiumBin}
    export PLAYWRIGHT_NODEJS_PATH=${nodejs}/bin/node
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
    exec ${bun}/bin/bun ${bundle}/share/bunjs-playwright-stealth-browser/playwright-stealth-browser.js "$@"
  '';
  meta = {
    description = "Playwright Chromium helper with rotating user agents";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "playwright-stealth-browser";
    platforms = lib.platforms.linux;
  };
}
