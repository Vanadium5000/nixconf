{
  buildNpmPackage,
  bun,
  coreutils,
  importNpmLock,
  lib,
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
    pname = "bunjs-quickshell-docs-mcp-bundle";
    version = "0-unstable";
    inherit src;
    npmDeps = importNpmLock { npmRoot = src; };
    npmConfigHook = importNpmLock.npmConfigHook;
    nativeBuildInputs = [ bun ];
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      bun build --target=bun --outfile=quickshell-docs-mcp.js quickshell-docs.ts
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm444 quickshell-docs-mcp.js "$out/share/bunjs-quickshell-docs-mcp/quickshell-docs-mcp.js"
      runHook postInstall
    '';
  };
in
writeShellApplication {
  name = "quickshell-docs-mcp";
  runtimeInputs = [
    bun
    coreutils
  ];
  text = ''
    exec ${bun}/bin/bun ${bundle}/share/bunjs-quickshell-docs-mcp/quickshell-docs-mcp.js "$@"
  '';
  meta = {
    description = "MCP server for Quickshell documentation";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "quickshell-docs-mcp";
    platforms = lib.platforms.linux;
  };
}
