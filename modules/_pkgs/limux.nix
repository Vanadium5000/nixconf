{
  lib,
  stdenv,
  callPackage,
  fetchFromGitHub,
  fetchpatch,
  rustPlatform,
  autoPatchelfHook,
  blueprint-compiler,
  wrapGAppsHook4,
  git,
  ncurses,
  pkg-config,
  python3,
  zig_0_15,
  gtk4,
  libadwaita,
  webkitgtk_6_0,
  gst_all_1,
  glib,
  cairo,
  pango,
  gdk-pixbuf,
  graphene,
  libGL,
  libepoxy,
  libxkbcommon,
  wayland,
  openssl,
  fontconfig,
  freetype,
  harfbuzz,
  glib-networking,
  libxml2,
  pkgs,
}:

let
  version = "0.1.19";
  src = fetchFromGitHub {
    owner = "am-will";
    repo = "limux";
    rev = "v${version}";
    hash = "sha256-49UqeLUZF9bn3JGRi6vXi1LYCPRAvCR9CdMlqWelQwY=";
    fetchSubmodules = true;
  };
  ghosttyBuildInputs = import (src + "/ghostty/nix/build-support/build-inputs.nix") {
    inherit pkgs lib stdenv;
  };
  giTypelibPath = import (src + "/ghostty/nix/build-support/gi-typelib-path.nix") {
    inherit pkgs lib stdenv;
  };
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "limux";
  inherit version src;

  # v0.1.19's release binaries render Ghostty into the wrong framebuffer size
  # on Wayland fractional scaling. Carry the upstream PR until the next release.
  # Ref: https://github.com/am-will/limux/pull/83
  patches = [
    (fetchpatch {
      url = "https://github.com/am-will/limux/pull/83.patch";
      hash = "sha256-l6GTHhlTyYt+aUFnpm0jS/mnDDFgWJTaepOWWKGWwzw=";
    })
  ];

  # Keep cargoDepsName version-invariant so the vendored Rust dependency output
  # stays cacheable across Limux version bumps when Cargo.lock is unchanged.
  # `cargoLock` import would be cleaner, but this nixpkgs' importCargoLock emits
  # a duplicate crates.io source for Limux's lockfile during cargo setup.
  # Source: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/rust.section.md#compiling-rust-applications-with-cargo
  cargoDepsName = "limux";
  cargoHash = "sha256-CdGjtN3NYqVP3FBTSlpGOMaHOgzgpoSPusFh14n+HWc=";

  deps = callPackage (src + "/ghostty/build.zig.zon.nix") {
    zig_0_15 = zig_0_15;
    name = "limux-zig-cache-${finalAttrs.version}";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    blueprint-compiler
    git
    libxml2
    ncurses
    pkg-config
    python3
    wrapGAppsHook4
    zig_0_15
  ];

  buildInputs = ghosttyBuildInputs ++ [
    stdenv.cc.cc.lib
    gtk4
    libadwaita
    webkitgtk_6_0
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
    gst_all_1.gst-libav
    glib
    cairo
    pango
    gdk-pixbuf
    graphene
    libGL
    libepoxy
    libxkbcommon
    wayland
    openssl
    fontconfig
    freetype
    harfbuzz
    glib-networking
  ];

  GI_TYPELIB_PATH = giTypelibPath;

  cargoBuildFlags = [ "--workspace" ];
  cargoTestFlags = [ "--workspace" ];

  postPatch = ''
    substituteInPlace .cargo/config.toml \
      --replace-fail /usr/local/lib/limux "$out/lib/limux"
    substituteInPlace ghostty/src/build/SharedDeps.zig \
      --replace-fail 'if (step.kind != .lib) {' 'if (true) {'
  '';

  preBuild = ''
    export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-global-cache
    export ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-local-cache

    ghosttyBuildFlags=(
      --system ${finalAttrs.deps}
      -Dcpu=baseline
      -Doptimize=ReleaseFast
      -Demit-docs=false
      -Demit-terminfo=true
      -fsys=fontconfig
      -fno-sys=freetype
      -fno-sys=harfbuzz
      -fno-sys=libpng
      -fno-sys=oniguruma
      -fno-sys=zlib
    )

    (cd ghostty && zig build -Dapp-runtime=none "''${ghosttyBuildFlags[@]}")
    (cd ghostty && DESTDIR=$TMPDIR/ghostty-install zig build --prefix /usr "''${ghosttyBuildFlags[@]}")

    # Limux links libghostty as an embedded shared library. Ghostty normally
    # compiles the GLAD OpenGL loader only into executables, so the patched
    # SharedDeps condition above adds GLAD to libghostty itself.
  '';

  buildPhase = ''
    runHook preBuild
    cargoBuildHook
    runHook postBuild
  '';

  preCheck = ''
    export LD_LIBRARY_PATH=$PWD/ghostty/zig-out/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  '';

  checkPhase = ''
    runHook preCheck
    cargo test --target ${stdenv.hostPlatform.rust.rustcTarget} --offline --target-dir target/check --profile release --workspace
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    cargoTargetDir=target/${stdenv.hostPlatform.rust.rustcTarget}/release

    install -Dm755 "$cargoTargetDir/limux-cli" $out/bin/limux
    install -Dm755 "$cargoTargetDir/limux" $out/libexec/limux/limux-host
    install -Dm644 ghostty/zig-out/lib/libghostty.so $out/lib/limux/libghostty.so

    mkdir -p $out/share/limux
    cp -r $TMPDIR/ghostty-install/usr/share/ghostty $out/share/limux/ghostty
    mkdir -p $out/share/limux/terminfo
    cp -r $TMPDIR/ghostty-install/usr/share/terminfo/g $out/share/limux/terminfo/
    cp -r $TMPDIR/ghostty-install/usr/share/terminfo/x $out/share/limux/terminfo/
    install -Dm644 rust/limux-host-linux/dev.limux.linux.desktop \
      $out/share/applications/dev.limux.linux.desktop
    install -Dm644 rust/limux-host-linux/dev.limux.linux.metainfo.xml \
      $out/share/metainfo/dev.limux.linux.metainfo.xml

    if [ -d rust/limux-host-linux/icons/hicolor ]; then
      cp -r rust/limux-host-linux/icons/hicolor $out/share/icons/
    fi
    for size in 16 32 128 256 512; do
      icon=rust/limux-host-linux/icons/app/$size.png
      if [ -f "$icon" ]; then
        install -Dm644 "$icon" $out/share/icons/hicolor/''${size}x''${size}/apps/limux.png
      fi
    done
    for icon in rust/limux-host-linux/icons/*.svg; do
      if [ -f "$icon" ]; then
        install -Dm644 "$icon" $out/share/icons/hicolor/scalable/actions/$(basename "$icon")
      fi
    done

    runHook postInstall
  '';

  appendRunpaths = [ "${placeholder "out"}/lib/limux" ];

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : "$out/lib/limux"
    )
  '';

  meta = {
    description = "GPU-accelerated terminal workspace manager for Linux";
    homepage = "https://github.com/am-will/limux";
    changelog = "https://github.com/am-will/limux/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "limux";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
})
