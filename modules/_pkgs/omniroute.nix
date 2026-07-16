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
  version = "3.8.48";
  docsSrc = fetchFromGitHub {
    owner = "diegosouzapw";
    repo = "OmniRoute";
    rev = "v${version}";
    hash = "sha256-lqw0M0mHqsMWWvz7X+3sO+FbaVmJ9bL9FBgB5HxsUBI=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "omniroute";
  inherit version;

  # Use the npm tarball because it is the supported CLI install artifact and
  # already contains the Next.js standalone app that upstream publishes.
  src = fetchurl {
    url = "https://registry.npmjs.org/omniroute/-/omniroute-${finalAttrs.version}.tgz";
    hash = "sha256-sJXyyGId+zdaSRDtYkMOhz7abuuRm1ZU1AeyHFk4MlU=";
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

  # Copy the GitHub lockfile, then drop pure-dev packages before fetchNpmDeps runs.
  # prefetch-npm-deps downloads every resolved lock entry (all platform optional
  # bindings for rolldown/etc.); that bulk CDN fetch is what fails update-pkgs on
  # HTTP/2 framing errors, and those packages are unused because the npm tarball
  # is prebuilt and installed with --omit=dev. Also strips package.json
  # devDependencies so npm ci stays consistent with the pruned lock.
  # Source: nixpkgs pkgs/build-support/node/prefetch-npm-deps
  # Source: https://github.com/diegosouzapw/OmniRoute/blob/v${version}/package-lock.json
  postPatch = ''
        cp ${docsSrc}/package-lock.json ./package-lock.json
        chmod u+w package-lock.json package.json
        # Heredoc body must stay unindented so Python does not see shell-level indent.
        ${lib.getExe python3} - <<'PY'
    import json
    from pathlib import Path

    lock_path = Path("package-lock.json")
    lock = json.loads(lock_path.read_text())
    packages = lock.get("packages", {})
    removed = 0
    for key in list(packages):
        if key and packages[key].get("dev") is True:
            del packages[key]
            removed += 1
    root = packages.get("")
    if isinstance(root, dict):
        root.pop("devDependencies", None)
    lock.pop("devDependencies", None)
    lock_path.write_text(json.dumps(lock, indent=2) + "\n")
    print(f"pruned {removed} dev-only packages from package-lock.json")

    pkg_path = Path("package.json")
    pkg = json.loads(pkg_path.read_text())
    if "devDependencies" in pkg:
        del pkg["devDependencies"]
        pkg_path.write_text(json.dumps(pkg, indent=2) + "\n")
        print("removed package.json devDependencies")
    PY
  '';

  # Hash of the pruned production dependency set from package-lock.json
  npmDepsHash = "sha256-oPWwJAJv40Eerpd7pwWkv9QYp/NYJrGPyB7bT5PbPZA=";
  # Upstream lock still carries install scripts that expect optional Bun payloads
  # when dev deps are present; keep install/prune on runtime deps only.
  npmInstallFlags = [ "--omit=dev" ];
  npmPruneFlags = [ "--omit=dev" ];
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

        # npm omniroute@3.8.42 published an empty serve.mjs while the matching
        # GitHub tag has the real CLI command; repair from the tagged source and
        # keep failing on unknown host-binding shapes so update-pkgs catches drift.
        # 3.8.48+ prefers OMNIROUTE_SERVER_HOST (then non-auto HOSTNAME) over
        # hard-coded 0.0.0.0; older shapes still get OMNIROUTE_HOST injected.
        # Source: https://github.com/diegosouzapw/OmniRoute/blob/v${version}/bin/cli/commands/serve.mjs
        serveCommand="$out/lib/omniroute/bin/cli/commands/serve.mjs"
        if [ ! -s "$serveCommand" ]; then
          cp ${docsSrc}/bin/cli/commands/serve.mjs "$serveCommand"
          chmod +x "$serveCommand"
        fi
        if grep -qE 'OMNIROUTE_SERVER_HOST|OMNIROUTE_HOST' "$serveCommand"; then
          :
        elif grep -q 'HOSTNAME: process.env.HOSTNAME || "0.0.0.0",' "$serveCommand"; then
          substituteInPlace "$serveCommand" \
            --replace-fail 'HOSTNAME: process.env.HOSTNAME || "0.0.0.0",' 'HOSTNAME: process.env.OMNIROUTE_HOST || process.env.HOSTNAME || "0.0.0.0",'
        elif grep -q 'HOSTNAME: "0.0.0.0",' "$serveCommand"; then
          substituteInPlace "$serveCommand" \
            --replace-fail 'HOSTNAME: "0.0.0.0",' 'HOSTNAME: process.env.OMNIROUTE_HOST || "0.0.0.0",'
        else
          echo "Unsupported OmniRoute serve host binding in $serveCommand" >&2
          exit 1
        fi

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
