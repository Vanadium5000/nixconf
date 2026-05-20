{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  autoPatchelfHook,
  makeWrapper,
  node-gyp,
  nodejs,
  openssl,
  pkg-config,
  python3,
  zlib,
}:

let
  version = "3.8.0";
  betterSqlite3Src = fetchurl {
    url = "https://registry.npmjs.org/better-sqlite3/-/better-sqlite3-12.9.0.tgz";
    hash = "sha256-rQ4pZQFAxJ0DNbHTVllqqBZvErdY9BiphEYTDjJ48lA=";
  };
  docsSrc = fetchFromGitHub {
    owner = "diegosouzapw";
    repo = "OmniRoute";
    rev = "v${version}";
    hash = "sha256-yDLv1yWY0Mr+46JylbElNTPgBtKkh6KpsH/bRAfqeEI=";
  };
  wreqJsSrc = fetchurl {
    url = "https://registry.npmjs.org/wreq-js/-/wreq-js-2.3.0.tgz";
    hash = "sha256-teKDtunTnMqR2+GOoPNJqdjln+gjkFh4iHBa5853B+s=";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "omniroute";
  inherit version;

  # Use the npm tarball because it is the supported CLI install artifact and
  # already contains the Next.js standalone app that upstream publishes.
  # Source: https://www.npmjs.com/package/omniroute
  src = fetchurl {
    url = "https://registry.npmjs.org/omniroute/-/omniroute-${finalAttrs.version}.tgz";
    hash = "sha256-UraSGU4LM+gD3feq2ExcB97e2CnDSBePwC3Jo1hLlDM=";
  };

  sourceRoot = "package";

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    node-gyp
    nodejs
    pkg-config
    python3
  ];

  buildInputs = [
    openssl
    stdenv.cc.cc.lib
    zlib
  ];

  # The npm standalone artifact includes koffi binaries for musl/OpenBSD; they
  # are not selected on this glibc Linux package but autoPatchelf still scans them.
  # Source: app/node_modules/koffi/build/koffi inside the published npm tarball.
  autoPatchelfIgnoreMissingDeps = [
    "libc.musl-x86_64.so.1"
    "libc++.so.9.0"
    "libc++abi.so.6.0"
    "libpthread.so.26.1"
    "libm.so.10.1"
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/omniroute" "$out/bin"
    cp -R . "$out/lib/omniroute"
    chmod +x "$out/lib/omniroute"/bin/*.mjs

    # The npm tarball omits markdown docs, but the compiled Next route traces
    # docs/*.md under app/docs and reads them via process.cwd().
    # Sources: https://github.com/diegosouzapw/OmniRoute/blob/v${finalAttrs.version}/src/app/docs/[slug]/page.tsx
    # and https://github.com/diegosouzapw/OmniRoute/blob/v${finalAttrs.version}/scripts/prepublish.ts
    rm -rf "$out/lib/omniroute/app/docs"
    cp -R ${docsSrc}/docs "$out/lib/omniroute/app/docs"

    # The standalone app ships a pruned wreq-js copy missing its ESM and native
    # files, while responses-ws-proxy imports it directly at runtime.
    # Source: https://github.com/diegosouzapw/OmniRoute/blob/v${finalAttrs.version}/scripts/postinstall.mjs
    rm -rf "$out/lib/omniroute/app/node_modules/wreq-js"
    mkdir -p "$out/lib/omniroute/app/node_modules/wreq-js"
    tar -xzf ${wreqJsSrc} -C "$out/lib/omniroute/app/node_modules/wreq-js" --strip-components=1

    # The standalone tarball also prunes better-sqlite3 to JS shims, but the
    # dashboard opens SQLite during batch polling and needs the native binding.
    # Source: https://www.npmjs.com/package/better-sqlite3/v/12.9.0;
    # the VPS journal shows bindings probing build/Release/better_sqlite3.node.
    rm -rf "$out/lib/omniroute/app/node_modules/better-sqlite3"
    mkdir -p "$out/lib/omniroute/app/node_modules/better-sqlite3"
    tar -xzf ${betterSqlite3Src} -C "$out/lib/omniroute/app/node_modules/better-sqlite3" --strip-components=1

    pushd "$out/lib/omniroute/app/node_modules/better-sqlite3" >/dev/null
    HOME="$TMPDIR" npm_config_nodedir=${nodejs} node-gyp rebuild --release
    popd >/dev/null

    test -f "$out/lib/omniroute/app/node_modules/better-sqlite3/build/Release/better_sqlite3.node"

    # The published tarball vendors runtime dependencies under app/node_modules,
    # while package-root helper scripts still resolve imports from ../node_modules
    # as they would after `npm install -g omniroute`.
    # Source: https://github.com/diegosouzapw/OmniRoute/blob/v${finalAttrs.version}/scripts/responses-ws-proxy.mjs
    ln -s app/node_modules "$out/lib/omniroute/node_modules"

    # Upstream's CLI forces the spawned Next.js server to 0.0.0.0. Keep that
    # default for CLI users, but give the NixOS service an explicit bind knob.
    # Source: https://github.com/diegosouzapw/OmniRoute/blob/v${finalAttrs.version}/bin/omniroute.mjs
    substituteInPlace "$out/lib/omniroute/bin/omniroute.mjs" \
      --replace-fail 'HOSTNAME: "0.0.0.0",' 'HOSTNAME: process.env.OMNIROUTE_HOST || "0.0.0.0",'

    makeWrapper ${nodejs}/bin/node "$out/bin/omniroute" \
      --add-flags "$out/lib/omniroute/bin/omniroute.mjs" \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}

    makeWrapper ${nodejs}/bin/node "$out/bin/omniroute-reset-password" \
      --add-flags "$out/lib/omniroute/bin/reset-password.mjs" \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]}

    runHook postInstall
  '';

  meta = {
    description = "OpenAI-compatible AI gateway with routing, fallbacks, caching, and observability";
    homepage = "https://github.com/diegosouzapw/OmniRoute";
    changelog = "https://github.com/diegosouzapw/OmniRoute/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "omniroute";
    platforms = lib.platforms.linux;
  };
})
