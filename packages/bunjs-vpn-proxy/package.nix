{
  buildNpmPackage,
  bun,
  importNpmLock,
  lib,
  runCommandLocal,
}:
let
  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      !(builtins.elem (baseNameOf path) [
        "node_modules"
        ".bun"
        "dist"
        "coverage"
      ]);
  };

  runtime = buildNpmPackage {
    pname = "bunjs-vpn-proxy-runtime";
    version = "0-unstable";
    inherit src;
    npmDeps = importNpmLock { npmRoot = src; };
    npmConfigHook = importNpmLock.npmConfigHook;
    nativeBuildInputs = [ bun ];

    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      export VPN_PROXY_WEB_DIST="$PWD/web-ui/dist"

      bun run build:web-ui
      bun build --target=bun --outfile=bundled/web-server.js web-server.ts
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/bunjs-vpn-proxy" "$out/share/vpn-proxy-web"
      cp bundled/web-server.js "$out/share/bunjs-vpn-proxy/web-server.js"
      cp -r web-ui/dist "$out/share/vpn-proxy-web/dist"
      cp *.ts netns.sh "$out/share/bunjs-vpn-proxy/"
      cp -r test-fixtures test-support "$out/share/bunjs-vpn-proxy/"
      runHook postInstall
    '';
  };
in
runtime
// {
  meta = {
    description = "SOCKS5 and HTTP CONNECT VPN proxy with a local web interface";
    homepage = "https://github.com/Vanadium5000/nixconf";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
