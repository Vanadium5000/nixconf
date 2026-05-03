{
  lib,
  buildNpmPackage,
  fetchurl,
  makeBinaryWrapper,
  playwright-driver,
  runCommand,
  versionCheckHook,
  writeShellScript,
}:

let
  version = "1.59.4";
  # Patchright 1.59.4 pins Chromium revision 1217 in patchright-core's
  # browsers.json, while this flake's nixpkgs Playwright bundle currently uses
  # revisioned directory names from its own package set.
  # Ref: patchright-core/browsers.json in the npm tarball.
  patchrightChromiumRevision = "1217";
  patchrightBrowsers = runCommand "patchright-browsers" { } ''
    mkdir -p "$out"
    for browser in ${playwright-driver.browsers}/*; do
      name="$(basename "$browser")"
      mkdir -p "$out/$name"
      for entry in "$browser"/*; do
        ln -s "$entry" "$out/$name/$(basename "$entry")"
      done
      if [ -e "$browser/chrome-linux" ] && [ ! -e "$out/$name/chrome-linux64" ]; then
        ln -s "$browser/chrome-linux" "$out/$name/chrome-linux64"
      fi
    done

    chromiumDir="$(basename ${playwright-driver.browsers}/chromium-*)"
    if [ "$chromiumDir" != "chromium-${patchrightChromiumRevision}" ]; then
      ln -s "$out/$chromiumDir" "$out/chromium-${patchrightChromiumRevision}"
    fi

    headlessDir="$(basename ${playwright-driver.browsers}/chromium_headless_shell-*)"
    if [ "$headlessDir" != "chromium_headless_shell-${patchrightChromiumRevision}" ]; then
      ln -s "$out/$headlessDir" "$out/chromium_headless_shell-${patchrightChromiumRevision}"
    fi
  '';
in
buildNpmPackage (finalAttrs: {
  pname = "patchright";
  inherit version;

  # Use the npm tarball because it is the artifact users install with `npm i`,
  # while GitHub release tags can lag the npm package version.
  # Ref: https://registry.npmjs.org/patchright/1.59.4
  src = fetchurl {
    url = "https://registry.npmjs.org/patchright/-/patchright-${version}.tgz";
    hash = "sha256-Wmxi6O7GF8EXKhmB46oGNiv7qodLyLLhm64nOvbIlYQ=";
  };

  sourceRoot = "package";

  # The published tarball omits package-lock.json, so keep a generated lockfile
  # beside the package for reproducible npm dependency vendoring.
  # Ref: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/npm.section.md#vendoring-deps
  postPatch = ''
    cp ${./patchright/package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-7FEClbedsEFQQdaXSJvcl6Oakh2+G2iDoqniwrbXWgE=";

  # Patchright ships prebuilt JavaScript in the npm tarball; skip package
  # scripts/build steps so packaging does not try mutable browser setup work.
  # Ref: https://www.npmjs.com/package/patchright?activeTab=code
  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  # Patchright's Chromium registry expects chrome-linux64, while nixpkgs'
  # Playwright bundle currently exposes chrome-linux; alias it instead of
  # downloading mutable browsers at runtime.
  # Ref: https://wiki.nixos.org/wiki/Playwright
  passthru.chromiumExecutablePath =
    let
      chromiumDir = builtins.head (
        builtins.filter (x: builtins.match "chromium-.*" x != null) (
          builtins.attrNames (builtins.readDir playwright-driver.browsers)
        )
      );
    in
    "${patchrightBrowsers}/${chromiumDir}/chrome-linux64/chrome";

  nativeBuildInputs = [ makeBinaryWrapper ];

  postFixup = ''
    wrapProgram $out/bin/patchright \
      --set PLAYWRIGHT_BROWSERS_PATH ${patchrightBrowsers} \
      --set-default PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
      --set-default PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS true
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = writeShellScript "version-check" ''
    "$1" --version >/dev/null
    echo "${finalAttrs.version}"
  '';
  versionCheckProgramArg = "${placeholder "out"}/bin/patchright";

  meta = {
    description = "Patched Playwright-compatible browser automation library";
    homepage = "https://github.com/Kaliiiiiiiiii-Vinyzu/patchright";
    changelog = "https://github.com/Kaliiiiiiiiii-Vinyzu/patchright/releases/tag/v${version}";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "patchright";
  };
})
