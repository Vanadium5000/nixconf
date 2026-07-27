{
  buildNpmPackage,
  bun,
  coreutils,
  importNpmLock,
  lib,
  markdownlint-cli,
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
    pname = "bunjs-markdown-lint-mcp-bundle";
    version = "0-unstable";
    inherit src;
    npmDeps = importNpmLock { npmRoot = src; };
    npmConfigHook = importNpmLock.npmConfigHook;
    nativeBuildInputs = [ bun ];
    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      bun build --target=bun --outfile=markdown-lint-mcp.js markdown-lint.ts
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm444 markdown-lint-mcp.js "$out/share/bunjs-markdown-lint-mcp/markdown-lint-mcp.js"
      runHook postInstall
    '';
  };
in
writeShellApplication {
  name = "markdown-lint-mcp";
  runtimeInputs = [
    bun
    coreutils
    markdownlint-cli
  ];
  text = ''
    exec ${bun}/bin/bun ${bundle}/share/bunjs-markdown-lint-mcp/markdown-lint-mcp.js "$@"
  '';
  meta = {
    description = "MCP server for Markdown linting";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    mainProgram = "markdown-lint-mcp";
    platforms = lib.platforms.linux;
  };
}
