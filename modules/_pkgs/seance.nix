{
  lib,
  stdenv,
  callPackage,
  fetchurl,
  wrapGAppsHook4,
  git,
  ncurses,
  pkg-config,
  zig_0_15,
  libnotify,
  libcanberra,
  adwaita-icon-theme,
  pkgs,
  revision ? "83013a4",
  optimize ? "ReleaseSafe",
}:
let
  version = "0.1.4";
  tarball = {
    # Upstream's release tarball vendors the Ghostty submodule; plain
    # fetchFromGitHub misses it and the Zig build cannot resolve libghostty.
    url = "https://github.com/no1msd/seance/releases/download/v${version}/seance-${version}-src.tar.gz";
    hash = "sha256-5ihq4uBz3s4kxQVHRQbVmhD3Y/1G80QzzouWUL449zk=";
    unpackedHash = "sha256-uJO3gso6hR66J6l1Z67+1gjNOvpb6E/WjrG7mfmtWLg=";
  };
  src = fetchurl {
    inherit (tarball) url hash;
  };
  source = builtins.fetchTarball {
    inherit (tarball) url;
    sha256 = tarball.unpackedHash;
  };
  ghosttyBuildInputs = import (source + "/ghostty/nix/build-support/build-inputs.nix") {
    inherit pkgs lib stdenv;
  };
  giTypelibPath = import (source + "/ghostty/nix/build-support/gi-typelib-path.nix") {
    inherit pkgs lib stdenv;
  };
  strip = optimize != "Debug" && optimize != "ReleaseSafe";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "seance";
  version = "${version}-${revision}";

  inherit src;

  deps = callPackage (source + "/ghostty/build.zig.zon.nix") {
    name = "seance-zig-cache-${finalAttrs.version}";
  };

  nativeBuildInputs = [
    git
    ncurses
    pkg-config
    zig_0_15
    wrapGAppsHook4
  ];

  buildInputs = ghosttyBuildInputs ++ [
    libnotify
    libcanberra
    adwaita-icon-theme
  ];

  dontConfigure = true;
  dontStrip = !strip;

  preBuild = ''
    export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache
    export ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-local-cache
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix XDG_DATA_DIRS : "${adwaita-icon-theme}/share"
    )
  '';

  GI_TYPELIB_PATH = giTypelibPath;

  zigBuildFlags = [
    "--system"
    "${finalAttrs.deps}"
    "-Dcpu=baseline"
    "-Doptimize=${optimize}"
    "-Dstrip=${lib.boolToString strip}"
  ];

  buildPhase = ''
    runHook preBuild

    buildCores=1
    if [ "''${enableParallelBuilding-1}" ]; then
      buildCores="$NIX_BUILD_CORES"
    fi

    TERM=dumb zig build -j"$buildCores" ${lib.escapeShellArgs finalAttrs.zigBuildFlags} --verbose

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    buildCores=1
    if [ "''${enableParallelInstalling-1}" ]; then
      buildCores="$NIX_BUILD_CORES"
    fi

    TERM=dumb zig build install -j"$buildCores" ${lib.escapeShellArgs finalAttrs.zigBuildFlags} --prefix "$out" --verbose

    runHook postInstall
  '';

  meta = {
    description = "GPU-accelerated terminal multiplexer with AI agent support";
    homepage = "https://github.com/no1msd/seance";
    changelog = "https://github.com/no1msd/seance/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "seance";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
})
