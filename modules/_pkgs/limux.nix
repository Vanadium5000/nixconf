{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  appstream-glib,
  desktop-file-utils,
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
    # Package the tarball release asset used by upstream's Arch template and
    # install.sh; it carries the CLI, host helper, Ghostty data, icons, metainfo,
    # and desktop file without RPM-specific paths.
    # update-pkgs: upstream release asset is limux-${version}-linux-x86_64.tar.gz.
    url = "https://github.com/am-will/limux/releases/download/v${finalAttrs.version}/limux-${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-94/s5Iugdf3vbiwwVviGhVe5tSBnDi4Cbsib3yzeNNg=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook4
    desktop-file-utils
    appstream-glib
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

  sourceRoot = "limux-${finalAttrs.version}-linux-x86_64";

  installPhase = ''
    runHook preInstall

    install -Dm755 limux $out/bin/limux
    install -Dm755 libexec/limux/limux-host $out/libexec/limux/limux-host
    install -Dm644 lib/libghostty.so $out/lib/limux/libghostty.so

    mkdir -p $out/share

    cp -r share/limux $out/share/
    install -Dm644 share/applications/*.desktop -t $out/share/applications/
    install -Dm644 share/metainfo/*.xml -t $out/share/metainfo/

    if [ -d share/icons/hicolor ]; then
      mkdir -p $out/share/icons
      cp -r share/icons/hicolor $out/share/icons/
    fi

    runHook postInstall
  '';

  appendRunpaths = [ "${placeholder "out"}/lib/limux" ];

  preFixup = ''
    gappsWrapperArgs+=(
      --unset LD_LIBRARY_PATH
      --unset GSK_RENDERER
      --set GDK_DISABLE gles-api,vulkan
      --set GHOSTTY_RESOURCES_DIR "$out/share/limux/ghostty"
      --set GHOSTTY_SHELL_INTEGRATION_XDG_DIR "$out/share/limux/ghostty/shell-integration"
      --set TERMINFO "$out/share/limux/terminfo"
    )

    limuxAddDriverRunpath() {
      for elf in \
        "$out/bin/.limux-wrapped" \
        "$out/libexec/limux/.limux-host-wrapped" \
        "$out/lib/limux/libghostty.so"
      do
        if [ -e "$elf" ]; then
          origRpath="$(patchelf --print-rpath "$elf")"
          patchelf --force-rpath --set-rpath "/run/opengl-driver/lib:$origRpath" "$elf"
        fi
      done
    }
    postFixupHooks+=(limuxAddDriverRunpath)
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/limux --help | grep -q "limux CLI"
    $out/libexec/limux/limux-host --version | grep -q "Limux ${finalAttrs.version}"

    # Upstream release packaging runs `git submodule update --init --recursive`
    # then builds Ghostty with `zig build -Dapp-runtime=none -Doptimize=ReleaseFast`.
    # The release tarball is the Nix input, so assert the resulting bundle pieces
    # are present rather than rebuilding an unpinned submodule during this derivation.
    test -f $out/lib/limux/libghostty.so
    test -d $out/share/limux/ghostty/themes
    test -d $out/share/limux/ghostty/shell-integration
    test -f $out/share/limux/terminfo/g/ghostty -o -f $out/share/limux/terminfo/x/xterm-ghostty

    # Upstream runs the release host with LD_LIBRARY_PATH=../ghostty/zig-out/lib.
    # The Nix package must not depend on mutable process env; libghostty lives in
    # $out/lib/limux and is found through the host binary RUNPATH instead.
    hostRpath="$(patchelf --print-rpath $out/libexec/limux/.limux-host-wrapped)"
    case ":$hostRpath:" in
      *":$out/lib/limux:"*) ;;
      *)
        echo "limux-host RUNPATH is missing $out/lib/limux" >&2
        exit 1
        ;;
    esac

    runHook postInstallCheck
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
