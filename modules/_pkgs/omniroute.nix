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
  version = "3.8.28";
  docsSrc = fetchFromGitHub {
    owner = "diegosouzapw";
    repo = "OmniRoute";
    rev = "v${version}";
    hash = "sha256-BRvpbhhLTYj2rKw+nZloaXkpu3ySs5sWZo9425xvAPs=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "omniroute";
  inherit version;

  # Use the npm tarball because it is the supported CLI install artifact and
  # already contains the Next.js standalone app that upstream publishes.
  src = fetchurl {
    url = "https://registry.npmjs.org/omniroute/-/omniroute-${finalAttrs.version}.tgz";
    hash = "sha256-/le4p5DSX5T7/srNuxVBLepzUPw8BgIVio+h0JnbfyY=";
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
  npmDepsHash = "sha256-Q1KLR3NkeFBB+tQzBazy+XWyIfpG8Magv+rdeqISNxw=";
  npmFlags = [ "--legacy-peer-deps" ];
  # onnxruntime-node downloads optional CUDA EP binaries when CPU binaries are
  # already bundled; the postinstall flag keeps npmDepsHash refreshes network-free.
  # Source: https://github.com/microsoft/onnxruntime/blob/v1.21.0/js/node/script/install.js
  env.ONNXRUNTIME_NODE_INSTALL_CUDA = "skip";

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

        # The docs app renders frontmatter values directly; gray-matter turns
        # unquoted YAML dates into Date objects, which React 19 rejects as children.
        mkdir -p "$out/lib/omniroute/app"
        rm -rf "$out/lib/omniroute/app/docs"
        cp -R ${docsSrc}/docs "$out/lib/omniroute/app/docs"
        python3 -c '
    import re
    import sys
    from pathlib import Path

    docs_root = Path(sys.argv[1])
    frontmatter = re.compile(r"\A---\n(.*?)\n---", re.S)
    last_updated = re.compile(r"(?m)^lastUpdated:\\s*(\\d{4}-\\d{2}-\\d{2})\\s*$")

    def patch_frontmatter(match):
        body = last_updated.sub(lambda date: f"lastUpdated: \"{date.group(1)}\"", match.group(1))
        return f"---\n{body}\n---"

    for path in docs_root.rglob("*"):
        if path.suffix not in {".md", ".mdx"}:
            continue
        content = path.read_text(encoding="utf-8")
        patched = frontmatter.sub(patch_frontmatter, content, count=1)
        if patched != content:
            path.write_text(patched, encoding="utf-8")
    ' "$out/lib/omniroute/app/docs"

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
