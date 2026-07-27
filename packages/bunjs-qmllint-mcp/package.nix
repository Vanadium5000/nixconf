{
  buildNpmPackage,
  bun,
  coreutils,
  importNpmLock,
  lib,
  qt6,
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
    pname = "bunjs-qmllint-mcp-bundle";
    version = "0-unstable";
    inherit src;
    npmDeps = importNpmLock { npmRoot = src; };
    npmConfigHook = importNpmLock.npmConfigHook;
    nativeBuildInputs = [ bun ];
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      bun build --target=bun --outfile=qmllint-mcp.js qmllint.ts
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm444 qmllint-mcp.js "$out/share/bunjs-qmllint-mcp/qmllint-mcp.js"
      runHook postInstall
    '';
  };
in
writeShellApplication {
  name = "qmllint-mcp";
  runtimeInputs = [
    bun
    coreutils
    qt6.qtdeclarative
  ];
  text = ''
    exec ${bun}/bin/bun ${bundle}/share/bunjs-qmllint-mcp/qmllint-mcp.js "$@"
  '';
  meta = {
    description = "MCP server for QML linting";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "qmllint-mcp";
    platforms = lib.platforms.linux;
  };
}
