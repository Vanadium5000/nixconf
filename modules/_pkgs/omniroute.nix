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
  version = "3.8.5";
  docsSrc = fetchFromGitHub {
    owner = "diegosouzapw";
    repo = "OmniRoute";
    rev = "v${version}";
    hash = "sha256-tcmHJD2qqE6TAItGGjQGPC8+4wZKldpa/4by8qREsLQ=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "omniroute";
  inherit version;

  # Use the npm tarball because it is the supported CLI install artifact and
  # already contains the Next.js standalone app that upstream publishes.
  src = fetchurl {
    url = "https://registry.npmjs.org/omniroute/-/omniroute-${finalAttrs.version}.tgz";
    hash = "sha256-mnyGgwvUtVsITm0gBlNdR3/sPY6ZmCAeEMhTSc8NEpw=";
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
  npmDepsHash = "sha256-Htr3IiA9VO9GakAjjegHvnuH082/AkAPCJdII9TXiJk=";
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

        # The docs app renders frontmatter values directly; gray-matter turns
        # unquoted YAML dates into Date objects, which React 19 rejects as children.
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
