{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook4,
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
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "limux";
  version = "0.1.19";

  src = fetchurl {
    # Use upstream's tarball, not the AppImage. The tarball layout is the one
    # known to render terminal and WebKit surfaces correctly on this host.
    # update-pkgs: upstream release asset is limux-${version}-linux-x86_64.tar.gz.
    url = "https://github.com/am-will/limux/releases/download/v${finalAttrs.version}/limux-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-jPDHMIc7JlVf3IecqZejJjEyjnGPmFaUWDdaNitqaEY=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook4
  ];

  buildInputs = [
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

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 limux $out/bin/limux
    if [ -x libexec/limux/limux-host ]; then
      install -Dm755 libexec/limux/limux-host $out/libexec/limux/limux-host
    fi
    install -Dm644 lib/libghostty.so $out/lib/limux/libghostty.so

    mkdir -p $out/share
    cp -r share/limux $out/share/
    install -Dm644 share/applications/dev.limux.linux.desktop \
      $out/share/applications/dev.limux.linux.desktop
    install -Dm644 share/metainfo/dev.limux.linux.metainfo.xml \
      $out/share/metainfo/dev.limux.linux.metainfo.xml
    if [ -d share/icons ]; then
      cp -r share/icons $out/share/
    fi

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
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
