{
  lib,
  fetchurl,
  appimageTools,
  gtk4,
  libadwaita,
  nss_latest,
  webkitgtk_6_0,
  adwaita-icon-theme,
  librsvg,
}:

let
  pname = "limux";
  version = "0.1.19";

  src = fetchurl {
    # Upstream currently publishes Linux builds as release assets; keep the
    # AppImage name from am-will/limux releases so update-pkgs can substitute
    # `${version}` and refresh this fixed-output hash automatically.
    url = "https://github.com/am-will/limux/releases/download/v${version}/Limux-${version}-x86_64.AppImage";
    hash = "sha256-x3vCkv+BNYspC+7mMWUBLz1Wrk9sEI0GcUlnVP2AriM=";
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;

    postExtract = ''
      chmod +w "$out/AppRun" "$out/usr/lib"

      # Limux 0.1.19 embeds GTK CSS custom properties and media queries but
      # its AppImage prepends Ubuntu 24.04-era GTK libraries that do not parse
      # them. Keep only bundled libghostty and use Nixpkgs GTK/WebKit instead.
      # Sources: https://docs.gtk.org/gtk4/css-properties.html#custom-properties
      # and upstream AppRun in ${src}.
      substituteInPlace "$out/AppRun" \
        --replace-fail 'export WEBKIT_EXEC_PATH="''${HERE}/usr/lib/webkitgtk-6.0"' 'export WEBKIT_EXEC_PATH="/usr/lib/webkitgtk-6.0"' \
        --replace-fail 'export WEBKIT_INJECTED_BUNDLE_PATH="''${HERE}/usr/lib/webkitgtk-6.0/injected-bundle"' 'export WEBKIT_INJECTED_BUNDLE_PATH="/usr/lib/webkitgtk-6.0/injected-bundle"'
      find "$out/usr/lib" -maxdepth 1 -type f ! -name libghostty.so -delete
      find "$out/usr/lib" -maxdepth 1 -type l ! -name libghostty.so -delete
      rm -rf "$out/usr/lib/webkitgtk-6.0"
    '';
  };
in
appimageTools.wrapAppImage {
  inherit pname version;
  src = appimageContents;

  extraPkgs = pkgs: [
    pkgs.dconf.lib
    pkgs.glib
    pkgs.glib-networking
    adwaita-icon-theme
    gtk4
    libadwaita
    librsvg
    nss_latest
    webkitgtk_6_0
  ];

  profile = ''
    # Sanitize host GI/GIO paths: this AppImage bundles GLib/OpenSSL, and
    # inherited modules have triggered gvfs/libproxy ABI errors. Sources:
    # https://docs.gtk.org/gio/running.html and
    # pkgs/build-support/build-fhsenv-bubblewrap/buildFHSEnv.nix:13,91-132.
    unset GIO_EXTRA_MODULES
    unset GI_TYPELIB_PATH

    # Prefer native Wayland while keeping X11 available for non-Wayland
    # sessions. cairo avoids GTK4 GL/Vulkan renderer failures without forcing
    # Xwayland. Source: https://docs.gtk.org/gtk4/running.html#environment-variables
    export GSK_RENDERER=cairo
    export GDK_BACKEND=wayland,x11
  '';

  extraInstallCommands = ''
    mkdir -p $out/share/applications

    # Desktop launchers and Limux data lookups need the AppImage's packaged
    # resources outside the FHS sandbox; copy upstream's usr/share layout plus
    # the root icon. Source: ${appimageContents}/usr/share and limux.png.
    cp -r ${appimageContents}/usr/share/icons $out/share/
    cp -r ${appimageContents}/usr/share/limux $out/share/
    cp -r ${appimageContents}/usr/share/metainfo $out/share/
    install -Dm644 ${appimageContents}/limux.png $out/share/pixmaps/${pname}.png

    cat > $out/share/applications/${pname}.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Limux
    Comment=GPU-accelerated terminal workspace manager
    Exec=${pname} %U
    Icon=${pname}
    Terminal=false
    Categories=System;TerminalEmulator;
    EOF
  '';

  meta = {
    description = "GPU-accelerated terminal workspace manager for Linux";
    homepage = "https://github.com/am-will/limux";
    changelog = "https://github.com/am-will/limux/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
