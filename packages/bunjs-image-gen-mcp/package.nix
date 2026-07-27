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
    pname = "bunjs-image-gen-mcp-bundle";
    version = "0-unstable";
    inherit src;
    npmDeps = importNpmLock { npmRoot = src; };
    npmConfigHook = importNpmLock.npmConfigHook;
    nativeBuildInputs = [ bun ];
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      bun build --target=bun --outfile=image-gen-mcp.js image-gen.ts
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm444 image-gen-mcp.js "$out/share/bunjs-image-gen-mcp/image-gen-mcp.js"
      runHook postInstall
    '';
  };
in
writeShellApplication {
  name = "image-gen-mcp";
  runtimeInputs = [
    bun
    coreutils
  ];
  text = ''
    exec ${bun}/bin/bun ${bundle}/share/bunjs-image-gen-mcp/image-gen-mcp.js "$@"
  '';
  meta = {
    description = "MCP server for image generation";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "image-gen-mcp";
    platforms = lib.platforms.linux;
  };
}
