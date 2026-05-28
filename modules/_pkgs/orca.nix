{
  lib,
  stdenv,
  fetchurl,
  buildPackages,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  autoPatchelfHook,
  cairo,
  coreutils,
  cups,
  dbus,
  dpkg,
  expat,
  fontconfig,
  freetype,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libglvnd,
  libnotify,
  libsecret,
  libuuid,
  libxkbcommon,
  nspr,
  nss,
  pango,
  udev,
  wayland,
  xdg-utils,
  xorg,
  commandLineArgs ? "",
  ...
}:

stdenv.mkDerivation rec {
  pname = "orca";
  version = "1.4.33";

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-ide_${version}_amd64.deb";
    hash = "sha256-8wwH3jAzuh+TKvYg0dH/FyOvcLt8QetdjfgWpybZWAQ=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    # Electron-builder emits GTK/GSettings-aware launchers; use the build
    # wrapper to avoid the wrong spliced makeWrapper in propagated inputs.
    # Source: nixpkgs pkgs/applications/editors/vscode/generic.nix.
    (buildPackages.wrapGAppsHook3.override { makeWrapper = buildPackages.makeShellWrapper; })
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    glib
    gtk3
    libdrm
    libgbm
    libglvnd
    libnotify
    libsecret
    libuuid
    libxkbcommon
    nspr
    nss
    pango
    udev
    wayland
    xorg.libX11
    xorg.libXScrnSaver
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXrender
    xorg.libXtst
    xorg.libxcb
    xorg.libxshmfence
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -R opt usr/share $out/

    chmod +x $out/opt/Orca/orca-ide \
      $out/opt/Orca/chrome_crashpad_handler \
      $out/opt/Orca/chrome-sandbox \
      $out/opt/Orca/resources/agent-browser-linux-x64
    chmod +x $out/opt/Orca/resources/bin/orca

    substituteInPlace $out/share/applications/orca-ide.desktop \
      --replace-fail /opt/Orca/orca-ide $out/bin/orca-ide

    ln -s $out/opt/Orca/orca-ide $out/bin/orca-ide
    ln -s $out/bin/orca-ide $out/bin/orca

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          xdg-utils
        ]
      }
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"
      --add-flags ${lib.escapeShellArg commandLineArgs}
    )
  '';

  postFixup = ''
    patchelf \
      --add-needed ${libglvnd}/lib/libGLESv2.so.2 \
      --add-needed ${libglvnd}/lib/libGL.so.1 \
      --add-needed ${libglvnd}/lib/libEGL.so.1 \
      $out/opt/Orca/orca-ide
  '';

  meta = {
    description = "IDE for orchestrating AI coding agents across terminals and worktrees";
    homepage = "https://github.com/stablyai/orca";
    downloadPage = "https://github.com/stablyai/orca/releases";
    changelog = "https://github.com/stablyai/orca/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "orca";
  };
}
