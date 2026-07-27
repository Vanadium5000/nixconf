{
  buildNpmPackage,
  importNpmLock,
  lib,
  runCommandLocal,
}:

let
  appSrc = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      let
        name = baseNameOf path;
      in
      !(builtins.elem name [
        "node_modules"
        ".docusaurus"
        "build"
      ]);
  };

  docsSrc = lib.cleanSourceWith {
    src = ../../docs;
    filter =
      path: _type:
      let
        name = baseNameOf path;
      in
      !(lib.hasPrefix "." name);
  };

  mergedSrc = runCommandLocal "bunjs-docs-src" { } ''
    mkdir -p "$out"
    cp -R ${appSrc}/. "$out/"
    chmod -R u+w "$out"
    cp -R ${docsSrc} "$out/docs"
  '';
in
buildNpmPackage {
  pname = "bunjs-docs";
  version = "0-unstable";
  src = mergedSrc;

  npmDeps = importNpmLock {
    npmRoot = appSrc;
  };
  npmConfigHook = importNpmLock.npmConfigHook;
  npmFlags = [ "--legacy-peer-deps" ];

  # `mergedSrc` copies repository docs beside the Docusaurus app instead of
  # retaining its checkout-relative `../../docs` position.
  NIXCONF_DOCS_ROOT = "./docs";
  env.DISABLE_VERSION_CHECK = "true";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/nixconf-docs"
    cp -r build/. "$out/share/nixconf-docs/"

    runHook postInstall
  '';

  meta = {
    description = "Static Docusaurus site for the NixOS configuration docs";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "nixconf-docs";
    platforms = lib.platforms.linux;
  };
}
