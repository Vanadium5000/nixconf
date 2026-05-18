{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs,
}:

buildNpmPackage rec {
  pname = "stdio-to-ws";
  version = "0.2.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@rebornix/stdio-to-ws/-/stdio-to-ws-${version}.tgz";
    hash = "sha256-0OuM3SR1rgap49Tf6l6RpD669BHIefr1jKBkr55Zwi0=";
  };

  npmDepsHash = "sha256-WtO6Ifzxw0YHMD/Yiz7Dnweb8jipoo+11QlJG40QqKA=";
  dontNpmBuild = true;
  npmInstallFlags = [ "--omit=dev" ];
  npmFlags = [ "--production" ];

  postPatch = ''
    cp ${./stdio-to-ws/package-lock.json} package-lock.json
    ${nodejs}/bin/node -e 'let p=require("./package.json"); delete p.devDependencies; delete p.scripts; require("fs").writeFileSync("package.json", JSON.stringify(p, null, 2))'
    # ACP stdio is newline-delimited, while ACP UI sends one JSON-RPC object per WebSocket frame; add the missing LF or `omp acp` keeps waiting for the initialize line. Source: https://agentclientprotocol.com/protocol/transports
    substituteInPlace dist/stdio-to-ws.js \
      --replace-fail 'child.stdin?.write(content);' 'child.stdin?.write(content.endsWith("\n") ? content : content + "\n");'
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    grep -F 'child.stdin?.write(content.endsWith("\n") ? content : content + "\n");' \
      "$out/lib/node_modules/@rebornix/stdio-to-ws/dist/stdio-to-ws.js"

    runHook postInstallCheck
  '';

  meta = {
    description = "Bridge stdio ACP agents to WebSocket clients";
    homepage = "https://github.com/rebornix/stdio-to-ws";
    license = lib.licenses.asl20;
    mainProgram = "stdio-to-ws";
    platforms = lib.platforms.linux;
  };
}
