{
  lib,
  stdenv,
  buildNpmPackage,
  fetchurl,
  fetchFromGitHub,
  autoPatchelfHook,
  makeWrapper,
  node-gyp,
  nodejs,
  openssl,
  pkg-config,
  libsecret,
  python3,
  zlib,
}:

let
  version = "3.8.0";
  docsSrc = fetchFromGitHub {
    owner = "diegosouzapw";
    repo = "OmniRoute";
    rev = "v${version}";
    hash = "sha256-yDLv1yWY0Mr+46JylbElNTPgBtKkh6KpsH/bRAfqeEI=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "omniroute";
  inherit version;

  # Use the npm tarball because it is the supported CLI install artifact and
  # already contains the Next.js standalone app that upstream publishes.
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
    libsecret
    openssl
    stdenv.cc.cc.lib
    zlib
  ];

  # Copy the lockfile from the GitHub repo to allow buildNpmPackage to run npm ci
  postPatch = ''
    cp ${docsSrc}/package-lock.json ./package-lock.json
  '';

  # Hash of the dependencies from package-lock.json
  npmDepsHash = "sha256-DKFMF4Bj+aWu/ORDpdYv+JP2ck3IrtQG4FkAeV2SheE=";
  npmFlags = [ "--legacy-peer-deps" ];

  dontNpmBuild = true;

  # The npm standalone artifact includes koffi binaries for musl/OpenBSD; they
  # are not selected on this glibc Linux package but autoPatchelf still scans them.
  autoPatchelfIgnoreMissingDeps = [
    "libc.musl-x86_64.so.1"
    "libc++.so.9.0"
    "libc++abi.so.6.0"
    "libpthread.so.26.1"
    "libm.so.10.1"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/omniroute" "$out/bin"
    cp -R . "$out/lib/omniroute"
    chmod +x "$out/lib/omniroute"/bin/*.mjs
    chmod +x "$out/lib/omniroute"/bin/cli/commands/*.mjs

    # Add the markdown docs missing from the tarball
    rm -rf "$out/lib/omniroute/app/docs"
    cp -R ${docsSrc}/docs "$out/lib/omniroute/app/docs"

    # Remove the pruned wreq-js and better-sqlite3 copies shipped in the standalone app.
    # Node will fallback to the fully-compiled ones in the root node_modules we built.
    rm -rf "$out/lib/omniroute/app/node_modules/wreq-js"
    rm -rf "$out/lib/omniroute/app/node_modules/better-sqlite3"

    # Upstream's CLI forces the spawned Next.js server to 0.0.0.0. Keep that
    # default for CLI users, but give the NixOS service an explicit bind knob.
    substituteInPlace "$out/lib/omniroute/bin/cli/commands/serve.mjs" \
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
