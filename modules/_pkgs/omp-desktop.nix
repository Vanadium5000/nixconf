{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook3,
  copyDesktopItems,
  makeDesktopItem,
  webkitgtk_4_1,
  libsoup_3,
  openssl,
  gtk3,
  glib,
  gdk-pixbuf,
  cairo,
  pango,
  atk,
  libayatana-appindicator,
  librsvg,
  glib-networking,
  gst_all_1,
  xdg-utils,
}:

rustPlatform.buildRustPackage rec {
  pname = "omp-desktop";
  version = "0.1.2";

  src = fetchFromGitHub {
    owner = "apoc";
    repo = "omp-desktop";
    rev = "v${version}";
    hash = "sha256-zU3EZhmpAE4HP7vdNL9UNBBOpxNoGySPV8E9pY5O8jE=";
  };

  sourceRoot = "${src.name}/src-tauri";

  cargoHash = "sha256-3I9T1w/DrtxqJ+7e2znKc5IScbFFNTVYh+Wt5xsHrLo=";

  nativeBuildInputs = [
    copyDesktopItems
    pkg-config
    wrapGAppsHook3
  ];

  buildInputs = [
    atk
    cairo
    gdk-pixbuf
    glib
    glib-networking
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gstreamer
    gtk3
    libayatana-appindicator
    libsoup_3
    librsvg
    openssl
    pango
    webkitgtk_4_1
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "omp-desktop";
      desktopName = "OMP Desktop";
      comment = "Desktop shell for the Oh My Pi coding agent";
      exec = "omp-desktop %U";
      icon = "omp-desktop";
      categories = [
        "Development"
        "Utility"
      ];
    })
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 \
      "target/${stdenv.hostPlatform.rust.rustcTarget}/release/omp-desktop" \
      "$out/bin/omp-desktop"

    for size in 16 32 64 128 512; do
      install -Dm644 "icons/''${size}x''${size}.png" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/omp-desktop.png"
    done

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}
    )
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test -x "$out/bin/omp-desktop"
    test -f "$out/share/applications/omp-desktop.desktop"
    test -f "$out/share/icons/hicolor/512x512/apps/omp-desktop.png"

    runHook postInstallCheck
  '';

  meta = {
    description = "Tauri desktop shell for the Oh My Pi coding agent";
    homepage = "https://github.com/apoc/omp-desktop";
    changelog = "https://github.com/apoc/omp-desktop/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "omp-desktop";
    platforms = [ "x86_64-linux" ];
  };
}
