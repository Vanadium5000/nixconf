{
  lib,
  buildNpmPackage,
  fetchurl,
  versionCheckHook,
  writeShellScript,
}:

let
  version = "1.59.4";
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
